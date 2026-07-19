import Foundation
import os

/// Reads media files using `ffprobe` and returns ``Container``s.
class Reader {
  private static let logger = Logger(subsystem: "SubTrack", category: "ffprobe")

  private let suppressStderr: Bool

  /// The URL to the `ffprobe` executable.
  var ffprobeURL =
    (try? which("ffprobe")) ?? URL(filePath: "ffprobe", directoryHint: .notDirectory)

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

    let process = Process()
    process.executableURL = ffprobeURL
    process.arguments = arguments
    process.standardInput = Pipe()

    let path = file.path(percentEncoded: false), tool = ffprobeURL.path(percentEncoded: false)
    Self.logger.debug("Probing \(path, privacy: .public) with \(tool, privacy: .public)")

    let (data, diagnosticsData) = try await process.runCapturingOutputAndError()
    // Decoded lossily on purpose: ffprobe's complaint is worth surfacing with a
    // U+FFFD in it, where the failable initializer would discard it entirely.
    // swiftlint:disable:next optional_data_string_conversion
    let diagnostics = String(decoding: diagnosticsData, as: UTF8.self)
    if !suppressStderr { FileHandle.standardError.write(diagnosticsData) }

    let exitCode = process.terminationStatus
    guard exitCode == 0 else {
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
