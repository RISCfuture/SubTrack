import Foundation

/**
 An operation to perform on a media file as part of a conversion process.

 Named `StreamOperation` rather than `Operation` to avoid colliding with
 `Foundation.Operation` (NSOperation) in code that imports both modules.
 */
public struct StreamOperation: Sendable, Equatable {

  /// The index of the stream to perform the operation on.
  public let streamIndex: UInt

  /// The stream content type.
  public let streamType: StreamType

  /// The type of operation to be performed.
  public let kind: Kind

  private var streamSelector: String { "0:\(streamIndex)" }

  /// The FFMPEG `-map` flag and its options.
  public var mapArgument: [String] { ["-map", streamSelector] }

  public init(streamIndex: UInt, streamType: StreamType, kind: Kind) {
    self.streamIndex = streamIndex
    self.streamType = streamType
    self.kind = kind
  }

  /**
   The FFMPEG `-c:x:N` argument and its options.

   `N` is the track's position among the output's streams of its own type, not
   its position in the source. A per-type `-c:a` would be a promise the plan
   can't keep: a plan that copies one audio track and converts another would
   emit both `-c:a copy` and `-c:a <codec>`, and FFMPEG applies whichever came
   last to every audio track.

   - Parameter outputIndex: The track's position among the output's streams of
     its own type.
   - Returns: The codec flag and its options.
   */
  public func codecArgument(outputIndex: Int) -> [String] {
    let codecFlag = "-c:\(streamType.rawValue):\(outputIndex)"
    switch kind {
      case let .convert(codec, arguments): return [codecFlag, codec] + arguments
      case .copy: return [codecFlag, "copy"]
    }
  }

  /// Stream types.
  public enum StreamType: String, Codable, Sendable, CaseIterable {

    /// Video stream.
    case video = "v"

    /// Audio stream.
    case audio = "a"

    /// Subtitle stream.
    case subtitle = "s"
  }

  /// Types of operations.
  public enum Kind: Equatable, Sendable {

    /// Copy (`-c:x copy`)
    case copy

    /// Convert (`-c:x <codec> [...]`)
    case convert(codec: String, arguments: [String])
  }
}
