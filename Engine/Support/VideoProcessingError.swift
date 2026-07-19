import Foundation

/**
 A failure while transcoding a media file with `ffmpeg` and verifying its
 output.

 All cases share the headline "Couldn't process the video."; the specific
 cause is carried by ``failureReason``.
 */
public enum VideoProcessingError: Error, Sendable {

  /// `ffmpeg` couldn't be launched.
  case launchFailed(detail: String)

  /// `ffmpeg` exited with a non-zero status.
  case encodeFailed(exitCode: Int32)

  /// The output is missing streams that were expected to be present.
  case outputMissingStreams(type: StreamOperation.StreamType, expected: UInt, found: UInt)

  /// An output stream was produced but contains no packet data.
  case outputStreamEmpty(streamIndex: Int, codec: String)

  /// Processing was cancelled before it finished.
  case cancelled
}

extension VideoProcessingError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t process the video.")
  }

  public var failureReason: String? {
    switch self {
      case .launchFailed(let detail):
        String(localized: "ffmpeg couldn’t be started: \(detail)")
      case .encodeFailed(let exitCode):
        String(localized: "ffmpeg exited with code \(exitCode, format: .number.grouping(.never)).")
      case let .outputMissingStreams(type, expected, found):
        String(
          localized:
            "Expected the \(type.displayName) output to contain \(expected) streams, but found \(found)."
        )
      case let .outputStreamEmpty(streamIndex, codec):
        String(
          localized:
            "Output stream \(streamIndex, format: .number.grouping(.never)) (\(codec)) contains no packets."
        )
      case .cancelled:
        String(localized: "Processing was cancelled.")
    }
  }
}

extension StreamOperation.StreamType {
  /// The name of this kind of stream as it reads inside user-facing prose.
  fileprivate var displayName: String {
    switch self {
      case .video: String(localized: "video")
      case .audio: String(localized: "audio")
      case .subtitle: String(localized: "subtitle")
    }
  }
}
