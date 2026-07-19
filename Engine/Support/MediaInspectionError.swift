import Foundation

/**
 A failure while reading and decoding a source media file with `ffprobe`.

 All cases share the headline "Couldn't read the video file."; the specific
 cause is carried by ``failureReason``.
 */
enum MediaInspectionError: Error, Sendable {

  /**
   `ffprobe` exited with a non-zero status. `detail` carries the last line it
   wrote to standard error, which is where it explains itself.
   */
  case probeFailed(exitCode: Int32, detail: String?)

  /**
   `ffprobe` produced no output for the file, which usually means it isn't a
   valid media container.
   */
  case noData(url: URL)

  /// The container has no video stream, which SubTrack requires.
  case noVideoStream(filename: String)

  /**
   `ffprobe` reported a stream whose `codec_type` isn't recognized. Also used
   as an internal signal while dispatching a stream to its concrete type.
   */
  case unknownStreamType(String)

  /// A numeric field in the `ffprobe` output couldn't be parsed.
  case malformedMetadata(field: String)

  /// The `ffprobe` JSON couldn't be decoded into a container.
  case decodingFailed(detail: String)
}

extension MediaInspectionError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t read the video file.")
  }

  public var failureReason: String? {
    switch self {
      case let .probeFailed(exitCode, detail):
        if let detail {
          String(
            localized:
              "ffprobe exited with code \(exitCode, format: .number.grouping(.never)): \(detail)"
          )
        } else {
          String(
            localized: "ffprobe exited with code \(exitCode, format: .number.grouping(.never))."
          )
        }
      case .noData(let url):
        String(localized: "ffprobe returned no data for “\(url.lastPathComponent)”.")
      case .noVideoStream(let filename):
        String(localized: "“\(filename)” doesn’t contain a video track.")
      case .unknownStreamType(let type):
        String(localized: "The stream type “\(type)” isn’t recognized.")
      case .malformedMetadata(let field):
        String(localized: "The “\(field)” value reported by ffprobe couldn’t be read.")
      case .decodingFailed(let detail):
        String(localized: "The ffprobe output couldn’t be decoded: \(detail)")
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .noVideoStream:
        String(localized: "Choose a file that contains a video track.")
      default:
        nil
    }
  }
}
