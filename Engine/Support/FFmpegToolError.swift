import Foundation

/**
 A problem locating or using the bundled or system `ffmpeg`/`ffprobe` tools.

 All cases share the headline "There's a problem with FFmpeg."; the specific
 cause is carried by ``failureReason``. Every case is user-actionable, so
 each provides a ``recoverySuggestion``.
 */
enum FFmpegToolError: Error, Sendable {

  /// The named executable couldn't be located.
  case executableNotFound(name: String)

  /// A required encoder isn't available in the current `ffmpeg` build.
  case unsupportedEncoder(codec: String)

  /// The `ffmpeg` build couldn't be probed for its capabilities.
  case probeUnavailable(detail: String)
}

extension FFmpegToolError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "There’s a problem with FFmpeg.")
  }

  public var failureReason: String? {
    switch self {
      case .executableNotFound(let name):
        String(localized: "The “\(name)” executable couldn’t be found.")
      case .unsupportedEncoder(let codec):
        String(localized: "The “\(codec)” encoder isn’t available in this build.")
      case .probeUnavailable(let detail):
        String(localized: "FFmpeg couldn’t be run: \(detail)")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .executableNotFound, .probeUnavailable:
        String(localized: "Set the FFmpeg location in Settings, or install it on your PATH.")
      case .unsupportedEncoder:
        String(localized: "Choose a supported codec, or use the downloadable version of SubTrack.")
    }
  }
}
