import Foundation

/// Anchors `Bundle(for:)` so the tests can find what the build put beside them.
private final class BundleAnchor {}

/**
 Runs the built `subtrack` executable and reports what it printed and exited
 with. The tool is tested as the artifact it ships as — a binary invoked with
 arguments — rather than by reaching into its types, which an executable target
 doesn't expose anyway.
 */
enum CLI {

  /// The `subtrack` binary, built alongside this test bundle by a target dependency.
  static let executable = Bundle(for: BundleAnchor.self)
    .bundleURL
    .deletingLastPathComponent()
    .appending(path: "subtrack", directoryHint: .notDirectory)

  /**
   The checked-in full `ffmpeg` build, located from this file rather than from a
   built app: the CLI's own target doesn't produce one, and resolving through
   `$PATH` would make the tests depend on whatever the machine happens to have.
   */
  static let vendoredFFmpeg = repositoryRoot.appending(path: "Vendor/ffmpeg-full/ffmpeg")
  static let vendoredFFprobe = repositoryRoot.appending(path: "Vendor/ffmpeg-full/ffprobe")

  private static let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // SubTrackCLITests
    .deletingLastPathComponent()  // repository root

  /**
   Runs `subtrack` with `arguments`, pointed at the vendored tools unless the
   caller passes its own `--ffmpeg`/`--ffprobe`.
   */
  static func run(_ arguments: [String], locateTools: Bool = true) throws -> Result {
    let tools =
      locateTools
      ? [
        "--ffmpeg", vendoredFFmpeg.path(percentEncoded: false),
        "--ffprobe", vendoredFFprobe.path(percentEncoded: false)
      ]
      : []
    return try execute(executable, arguments: tools + arguments)
  }

  /**
   Runs any executable to completion, capturing both streams.

   Output is collected through temporary files rather than pipes: a pipe whose
   buffer fills while nothing is draining it deadlocks the child, and `ffmpeg`
   is talkative enough to reach that.
   */
  @discardableResult
  static func execute(_ executable: URL, arguments: [String]) throws -> Result {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "subtrack-cli-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let outURL = directory.appending(path: "stdout")
    let errURL = directory.appending(path: "stderr")
    FileManager.default.createFile(atPath: outURL.path(percentEncoded: false), contents: nil)
    FileManager.default.createFile(atPath: errURL.path(percentEncoded: false), contents: nil)

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let outHandle = try FileHandle(forWritingTo: outURL)
    let errHandle = try FileHandle(forWritingTo: errURL)
    process.standardOutput = outHandle
    process.standardError = errHandle
    try process.run()
    process.waitUntilExit()
    try? outHandle.close()
    try? errHandle.close()

    return Result(
      exitCode: process.terminationStatus,
      standardOutput: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
      standardError: (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
    )
  }

  /// What one invocation produced.
  struct Result {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { exitCode == 0 }

    /**
     The operation lines of a `--dry-run` plan, without the `input -> output:`
     header and with the leading indent removed — e.g. `["0:0 (video): copy"]`.
     Everything before the header is `ffprobe`'s own banner.
     */
    var plan: [String] {
      guard let header = standardOutput.firstIndex(of: ">") else { return [] }
      return standardOutput[header...]
        .split(separator: "\n")
        .dropFirst()
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }
  }
}
