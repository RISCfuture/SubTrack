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
   container `default` and take that flag off every other audio track, so a
   language-prioritized output isn't overridden by a `default` flag copied
   from a lower-priority source track. `N` is the output-relative audio index,
   i.e. the track's position among the audio operations in `-map` order.
   Empty when there is no audio; video and subtitle dispositions are untouched.

   `+default` and `-default` add and remove that one flag from whatever the
   source track carried. A bare `0` would wipe the whole set, and a commentary
   track kept on purpose would come out of the run with nothing saying so.
   */
  static func dispositionArguments(for operations: [StreamOperation]) -> [String] {
    operations.filter { $0.streamType == .audio }.indices.flatMap { index in
      ["-disposition:a:\(index)", index == 0 ? "+default" : "-default"]
    }
  }

  /**
   Runs the conversion, delivering progress via `onProgress`.

   `ffmpeg` writes into a staging file, which is moved onto the destination
   only once the run has exited cleanly and verified. The destination
   therefore ends up either untouched or complete — never holding the
   truncated remains of a cancelled or failed run, and never losing a good
   earlier file to a retry that goes wrong.
   */
  func process(
    outputURL: URL,
    onProgress: @escaping @Sendable (ConversionProgress) -> Void
  ) async throws {
    let staged = StagedOutput(destination: outputURL)
    let writeURL = staged?.url ?? outputURL

    let running = RunningProcess()
    let process = running.process
    let stdout = configure(process, writingTo: writeURL)

    let duration = totalDuration
    let readHandle = stdout.fileHandleForReading, writeHandle = stdout.fileHandleForWriting

    do {
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
        if verifyOutput { try await verify(outputURL: writeURL) }
      } onCancel: {
        running.terminate()
      }
    } catch {
      staged?.discard()
      throw error
    }

    // Reaching here means `ffmpeg` exited zero and the output holds what was
    // planned, which is the whole precondition for publishing it.
    try staged?.commit()
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
 The file a run writes into, and the move that publishes it once the run has
 proven itself.

 The staging directory sits on the destination's own volume, so the commit is
 a rename rather than a copy. The staged file keeps the destination's name
 because `ffmpeg` picks its muxer from the extension.
 */
private struct StagedOutput {

  /// Where `ffmpeg` writes.
  let url: URL

  private let directory: URL
  private let destination: URL

  /**
   The staged file, when a failed move has left it behind. `replaceItemAt`
   makes no promise about the replacement it was handed once it throws, so
   whether there is still a file to point the user at is a question to ask
   rather than assume.
   */
  private var survivingStagedFile: URL? {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
  }

  /**
   Prepares a staging directory for `destination`, or fails when one can't be
   had — a destination that names no ordinary file, or a folder that won't take
   a new directory. A run that can't stage writes straight to its destination
   instead, which is worth more than refusing to run at all.
   */
  init?(destination: URL) {
    guard let directory = Self.makeStagingDirectory(for: destination) else { return nil }

    self.directory = directory
    self.destination = destination
    self.url = directory.appending(
      path: destination.lastPathComponent,
      directoryHint: .notDirectory
    )
  }

  /**
   Foundation's item-replacement directory where the run can have one, and a
   directory inside the destination's own folder where it can't.

   The item-replacement directory is the better home of the two: it is on the
   destination's volume, and the system clears it away after a crash. It is
   only dependably available for a boot-volume destination, though, where
   Foundation places it in the process's temporary directory. Elsewhere it goes
   to the volume root, which a sandboxed run holding a bookmark for the
   destination *folder* has no access to — so on an external drive or a network
   share, staging inside that folder is the one place the run is certain to
   reach.
   */
  private static func makeStagingDirectory(for destination: URL) -> URL? {
    let fileManager = FileManager.default
    if let replacement = try? fileManager.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: destination,
      create: true
    ) {
      return replacement
    }

    let inDestinationFolder = destination.deletingLastPathComponent()
      .appending(path: ".SubTrack-\(UUID().uuidString)", directoryHint: .isDirectory)
    do {
      try fileManager.createDirectory(at: inDestinationFolder, withIntermediateDirectories: false)
      return inDestinationFolder
    } catch {
      return nil
    }
  }

  /**
   Moves the staged file onto the destination and clears the staging directory
   away.

   `replaceItemAt` needs something to replace and fails when the destination
   doesn't exist yet, which is the ordinary case for a first run — hence the
   two paths. A file appearing in the window between the check and the move
   makes `moveItem` throw, which fails the run without destroying anything.

   The replacement takes the new file's own dates and permissions: this is a
   freshly produced encode rather than a new revision of what was there.

   A move that fails leaves the staged file where it is and names it in the
   error. The run has a verified encode in hand by this point, and a
   destination gone read-only, full, or absent is worth reporting without also
   throwing the work away.
   */
  func commit() throws {
    do {
      try moveOntoDestination()
    } catch {
      throw VideoProcessingError.outputCommitFailed(
        stagedURL: survivingStagedFile,
        detail: error.userMessage
      )
    }
    discard()
  }

  private func moveOntoDestination() throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
      _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: url,
        backupItemName: nil,
        options: [.usingNewMetadataOnly]
      )
    } else {
      try fileManager.moveItem(at: url, to: destination)
    }
  }

  /**
   Removes the staging directory and whatever is still in it — the partial file
   a failed or cancelled run left behind, or the finished one a commit has
   already moved out.
   */
  func discard() {
    try? FileManager.default.removeItem(at: directory)
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
