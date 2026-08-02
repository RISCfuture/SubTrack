import Foundation

/**
 Processes a video file with `ffmpeg`, streaming progress updates parsed from
 `ffmpeg -progress pipe:1`. Supports cooperative cancellation (terminating the
 `ffmpeg` child) and the same post-run re-probe verification as the CLI.
 */
final class ProgressReportingProcessor: Processor {

  /// The URL path to the `ffmpeg` executable.
  var ffmpegURL =
    (try? which("ffmpeg")) ?? URL(filePath: "ffmpeg", directoryHint: .notDirectory)

  /// The URL path to the `ffprobe` executable (used for post-process verification).
  var ffprobeURL =
    (try? which("ffprobe")) ?? URL(filePath: "ffprobe", directoryHint: .notDirectory)

  /// If `true`, `ffmpeg`'s `stderr` output is discarded.
  var suppressStderr = false

  /**
   If `true`, the output is re-probed after `ffmpeg` exits and an error is
   thrown if any expected stream is missing or empty.
   */
  var verifyOutput = true

  /**
   The source duration, used to turn `ffmpeg`'s elapsed output time into a
   completion fraction.
   */
  var totalDuration: Duration = .zero

  private let inputURL: URL

  let operations: [StreamOperation]

  init(inputURL: URL, operations: [StreamOperation]) {
    self.inputURL = inputURL
    self.operations = operations
  }

  /**
   The `-c:x:N` flags for `operations`, each numbered by its position among the
   output's streams of its own type — i.e. its `-map` order within that type.

   Numbering here rather than on the operation itself is what keeps a mixed
   plan honest: only the whole list knows where a given track lands among its
   own kind.
   */
  static func codecArguments(for operations: [StreamOperation]) -> [String] {
    var writtenPerType = [StreamOperation.StreamType: Int]()
    return operations.flatMap { operation in
      let outputIndex = writtenPerType[operation.streamType, default: 0]
      writtenPerType[operation.streamType] = outputIndex + 1
      return operation.codecArgument(outputIndex: outputIndex)
    }
  }

  /**
   The `-disposition:a:N` flags that mark the first kept audio track as the
   container `default` and clear the flag on every other audio track, so a
   language-prioritized output isn't overridden by a `default` flag copied
   from a lower-priority source track. `N` is the output-relative audio index,
   i.e. the track's position among the audio operations in `-map` order.
   Empty when there is no audio; video and subtitle dispositions are untouched.
   */
  static func dispositionArguments(for operations: [StreamOperation]) -> [String] {
    operations.filter { $0.streamType == .audio }.indices.flatMap { index in
      ["-disposition:a:\(index)", index == 0 ? "default" : "0"]
    }
  }

  /// Runs the conversion, delivering progress via `onProgress`.
  func process(
    outputURL: URL,
    onProgress: @escaping @Sendable (ConversionProgress) -> Void
  ) async throws {
    let running = RunningProcess()
    let process = running.process
    let stdout = configure(process, writingTo: outputURL)

    let duration = totalDuration
    let readHandle = stdout.fileHandleForReading, writeHandle = stdout.fileHandleForWriting

    try await withTaskCancellationHandler {
      // Reads only local, Sendable-transferable values (never `self`), so the
      // non-Sendable processor is not sent into the child task.
      async let reading: Void = {
        var parser = ProgressParser(totalDuration: duration)
        for try await line in readHandle.bytes.lines {
          if let progress = parser.consume(line: line) { onProgress(progress) }
        }
      }()

      do {
        try await process.runUntilExit()
      } catch {
        // Nothing spawned, so close the write end here too — the reader above
        // would otherwise wait forever for an EOF no child can deliver.
        try? writeHandle.close()
        if Task.isCancelled { throw VideoProcessingError.cancelled }
        throw VideoProcessingError.launchFailed(detail: error.userMessage)
      }
      // Close the parent's copy of the write end so the reader sees EOF.
      try? writeHandle.close()
      try await reading

      if Task.isCancelled { throw VideoProcessingError.cancelled }
      guard process.terminationStatus == 0 else {
        throw VideoProcessingError.encodeFailed(exitCode: process.terminationStatus)
      }
      if verifyOutput { try await verify(outputURL: outputURL) }
    } onCancel: {
      running.terminate()
    }
  }

  /// The full `ffmpeg` argument vector for this conversion.
  private func arguments(outputURL: URL) -> [String] {
    let convertArguments =
      Self.codecArguments(for: operations) + operations.flatMap(\.mapArgument)
    return ["-y", "-i", inputURL.path(percentEncoded: false)] + convertArguments
      + Self.dispositionArguments(for: operations)
      + ["-progress", "pipe:1", "-nostats", outputURL.path(percentEncoded: false)]
  }

  /**
   Points `process` at `ffmpeg` with this conversion's arguments and pipes,
   returning the pipe carrying the `-progress` stream.
   */
  private func configure(_ process: Process, writingTo outputURL: URL) -> Pipe {
    let stdout = Pipe()
    process.executableURL = ffmpegURL
    process.arguments = arguments(outputURL: outputURL)
    process.standardOutput = stdout
    process.standardInput = Pipe()
    if suppressStderr { process.standardError = FileHandle.nullDevice }
    return stdout
  }

  private func verify(outputURL: URL) async throws {
    let reader = Reader(suppressStderr: suppressStderr)
    reader.ffprobeURL = ffprobeURL
    let output = try await reader.open(file: outputURL, countPackets: true)

    var expectedByType = [StreamOperation.StreamType: UInt]()
    for operation in operations { expectedByType[operation.streamType, default: 0] += 1 }
    let actualByType: [StreamOperation.StreamType: UInt] = [
      .video: UInt(output.videoStreams.count),
      .audio: UInt(output.audioStreams.count),
      .subtitle: UInt(output.subtitleStreams.count)
    ]
    for (type, expected) in expectedByType {
      let actual = actualByType[type] ?? 0
      if actual != expected {
        throw VideoProcessingError.outputMissingStreams(
          type: type,
          expected: expected,
          found: actual
        )
      }
    }

    let coded =
      (output.videoStreams as [any CodedStream]) + (output.audioStreams as [any CodedStream])
      + (output.subtitleStreams as [any CodedStream])
    for stream in coded where stream.nbReadPackets == nil || stream.nbReadPackets == 0 {
      throw VideoProcessingError.outputStreamEmpty(
        streamIndex: Int(stream.index),
        codec: stream.codecName
      )
    }
  }
}

/**
 A minimal `Sendable` box around a `Process` so a task-cancellation handler
 can terminate the child `ffmpeg` from outside the running actor context.
 `Process.terminate()` is safe to call from another thread.
 */
private final class RunningProcess: @unchecked Sendable {
  let process = Process()

  func terminate() {
    if process.isRunning { process.terminate() }
  }
}
