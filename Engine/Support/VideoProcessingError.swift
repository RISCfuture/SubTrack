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

  /**
   The output was encoded and verified, but couldn't be moved onto its
   destination. `stagedURL` is where the finished file was left, and `nil` when
   the failed move took it with it.
   */
  case outputCommitFailed(stagedURL: URL?, detail: String)

  /// Processing was cancelled before it finished.
  case cancelled
}

extension VideoProcessingError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t process the video.", bundle: #bundle)
  }

  public var failureReason: String? {
    switch self {
      case .launchFailed(let detail):
        String(localized: "ffmpeg couldn’t be started: \(detail)", bundle: #bundle)
      case .encodeFailed(let exitCode):
        String(
          localized: "ffmpeg exited with code \(exitCode, format: .number.grouping(.never)).",
          bundle: #bundle
        )
      case let .outputMissingStreams(type, expected, found):
        String(
          localized:
            "Expected the \(type.displayName) output to contain \(expected) streams, but found \(found).",
          bundle: #bundle
        )
      case let .outputStreamEmpty(streamIndex, codec):
        String(
          localized:
            "Output stream \(streamIndex, format: .number.grouping(.never)) (\(codec)) contains no packets.",
          bundle: #bundle
        )
      case .outputCommitFailed(_, let detail):
        String(
          localized: "The video was encoded, but couldn’t be moved into place. \(detail)",
          bundle: #bundle
        )
      case .cancelled:
        String(localized: "Processing was cancelled.", bundle: #bundle)
    }
  }

  /**
   Only a failed commit leaves the user something to act on: the encode
   survived, and its path is the one thing standing between them and it.
   */
  public var recoverySuggestion: String? {
    guard case .outputCommitFailed(let stagedURL?, _) = self else { return nil }
    return String(
      localized: "The finished file is at “\(stagedURL.path(percentEncoded: false))”.",
      bundle: #bundle
    )
  }

  /**
   A failure to launch is a problem with the `ffmpeg` build itself; the rest
   are a run that started and then went wrong. Cancelling, and a finished
   encode the file system wouldn't take, are neither.
   */
  public var helpAnchor: String? {
    switch self {
      case .launchFailed: HelpAnchor.customFFmpeg.rawValue
      case .encodeFailed, .outputMissingStreams, .outputStreamEmpty:
        HelpAnchor.encodeFailed.rawValue
      case .outputCommitFailed, .cancelled: nil
    }
  }
}

extension StreamOperation.StreamType {
  /// The name of this kind of stream as it reads inside user-facing prose.
  fileprivate var displayName: String {
    switch self {
      case .video: String(localized: "video", bundle: #bundle)
      case .audio: String(localized: "audio", bundle: #bundle)
      case .subtitle: String(localized: "subtitle", bundle: #bundle)
    }
  }
}
