import Foundation
import Subprocess
import System
import os

/// Reads media files using `ffprobe` and returns ``Container``s.
class Reader {
  private static let logger = Logger(subsystem: "SubTrack", category: "ffprobe")

  /**
   The most `ffprobe` may write to either stream. Its JSON scales with the
   number of streams rather than the length of the movie, and its diagnostics
   are a banner and a few lines, so a megabyte is generous for both.
   */
  private static let outputLimit = 1 << 20

  private let suppressStderr: Bool

  /// The URL to the `ffprobe` executable, which the caller resolves.
  var ffprobeURL = URL(filePath: "ffprobe", directoryHint: .notDirectory)

  /**
   Creates a new instance.

   - Parameter suppressStderr: If `true`, `stderr` output will not be printed.
   */
  init(suppressStderr: Bool = false) {
    self.suppressStderr = suppressStderr
  }

  /**
   The last meaningful line of `ffprobe`'s diagnostics — where its actual
   complaint lands, past the banner and any warnings.
   */
  private static func complaint(in diagnostics: String) -> String? {
    diagnostics.split(whereSeparator: \.isNewline)
      .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  /**
   Whether the system is withholding `file`: it is there, but this process is
   not allowed to read it. macOS refuses another app's container without
   prompting, and a process with no bundle identifier — which is what the
   `subtrack` tool is — cannot be granted access to one at all. A path that
   isn't there at all is `ffprobe`'s to complain about.
   */
  private static func isWithheld(_ file: URL) -> Bool {
    let manager = FileManager.default, path = file.path(percentEncoded: false)
    return manager.fileExists(atPath: path) && !manager.isReadableFile(atPath: path)
  }

  /**
   Reads a media file and creates a Container.

   - Parameter file: The path to the container file.
   - Parameter countPackets: If `true`, `-count_packets` is passed to
   `ffprobe`, populating each ``CodedStream``'s ``CodedStream/nbReadPackets``
   property. Slower, since `ffprobe` has to read every packet in the file.
   - Returns: The parsed Container.
   */
  func `open`(file: URL, countPackets: Bool = false) async throws -> Container {
    var arguments = [
      "-print_format", "json", "-show_format", "-show_streams", file.path(percentEncoded: false)
    ]
    if countPackets { arguments.insert("-count_packets", at: 0) }
    guard FileManager.default.isExecutableFile(atPath: ffprobeURL.path(percentEncoded: false))
    else {
      throw FFmpegToolError.executableNotFound(name: "ffprobe")
    }
    guard !Self.isWithheld(file) else { throw MediaInspectionError.accessDenied(url: file) }

    let path = file.path(percentEncoded: false), tool = ffprobeURL.path(percentEncoded: false)
    Self.logger.debug("Probing \(path, privacy: .public) with \(tool, privacy: .public)")

    let result = try await Subprocess.run(
      .path(FilePath(tool)),
      arguments: Arguments(arguments),
      output: .data(limit: Self.outputLimit),
      error: .data(limit: Self.outputLimit)
    )
    let data = result.standardOutput, diagnosticsData = result.standardError
    // Decoded lossily on purpose: ffprobe's complaint is worth surfacing with a
    // U+FFFD in it, where the failable initializer would discard it entirely.
    // swiftlint:disable:next optional_data_string_conversion
    let diagnostics = String(decoding: diagnosticsData, as: UTF8.self)
    if !suppressStderr { FileHandle.standardError.write(diagnosticsData) }

    guard result.terminationStatus.isSuccess else {
      let exitCode = result.terminationStatus.code
      Self.logger.error(
        "ffprobe exited with code \(exitCode) for \(path, privacy: .public): \(diagnostics, privacy: .public)"
      )
      throw MediaInspectionError.probeFailed(
        exitCode: exitCode,
        detail: Self.complaint(in: diagnostics)
      )
    }
    guard !data.isEmpty else {
      Self.logger.error(
        "ffprobe returned no output for \(path, privacy: .public): \(diagnostics, privacy: .public)"
      )
      throw MediaInspectionError.noData(url: file)
    }

    do {
      return try JSONDecoder().decode(Container.self, from: data)
    } catch let error as MediaInspectionError {
      throw error
    } catch {
      throw MediaInspectionError.decodingFailed(detail: String(describing: error))
    }
  }
}
