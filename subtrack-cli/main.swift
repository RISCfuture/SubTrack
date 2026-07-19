import Foundation

/**
 `subtrack` — the command-line counterpart to the SubTrack app, sharing the
 same engine. Slims a single video file, mirroring the VideoSlimmer CLI.
 */
func run(_ options: CommandOptions) async throws {
  guard let input = options.input, let output = options.output else {
    throw CLIUsageError.wrongArgumentCount
  }

  let ffmpegURL = try resolve(options.ffmpeg, orLocate: "ffmpeg")
  let ffprobeURL = try resolve(options.ffprobe, orLocate: "ffprobe")

  let reader = Reader(suppressStderr: options.suppressStderr)
  reader.ffprobeURL = ffprobeURL
  let container = try await reader.open(file: input)
  let operations = try options.rules.makeConverter(container: container).operations()

  if options.dryRun {
    try await DryRunProcessor(inputURL: input, operations: operations).process(outputURL: output)
    return
  }

  let processor = ProgressReportingProcessor(inputURL: input, operations: operations)
  processor.ffmpegURL = ffmpegURL
  processor.ffprobeURL = ffprobeURL
  processor.suppressStderr = options.suppressStderr
  processor.verifyOutput = !options.skipVerify
  processor.totalDuration = .seconds(container.durationSec)

  if options.skipNoops && processor.isNoop(container: container) { return }

  try await processor.process(outputURL: output) { progress in
    guard let fraction = progress.fraction else { return }
    let line = String(
      localized: "Progress: \(fraction, format: .percent.precision(.fractionLength(0)))"
    )
    FileHandle.standardError.write(Data("\r\(line)".utf8))
  }
  FileHandle.standardError.write(Data("\r\(String(localized: "Done."))        \n".utf8))
}

/// Uses an explicit path if provided, otherwise locates the executable on `$PATH`.
private func resolve(_ explicit: URL?, orLocate name: String) throws -> URL {
  if let explicit { return explicit }
  guard let located = try which(name) else { throw FFmpegToolError.executableNotFound(name: name) }
  return located
}

private func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(code)
}

do {
  switch try CommandOptions.parse(Array(CommandLine.arguments.dropFirst())) {
    case .help(let text): print(text)
    case .options(let options): try await run(options)
  }
} catch {
  fail(String(localized: "Error: \(error.userMessage)"), code: 1)
}
