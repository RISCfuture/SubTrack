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

  private var codecFlag: String { "-c:\(streamType.rawValue)" }
  private var streamSelector: String { "0:\(streamIndex)" }

  /// The FFMPEG `-map` flag and its options.
  public var mapArgument: [String] { ["-map", streamSelector] }

  /// The FFMPEG `-c:x` argument and its options.
  public var codecArgument: [String] {
    switch kind {
      case let .convert(codec, arguments): return [codecFlag, codec] + arguments
      case .copy: return [codecFlag, "copy"]
    }
  }

  public init(streamIndex: UInt, streamType: StreamType, kind: Kind) {
    self.streamIndex = streamIndex
    self.streamType = streamType
    self.kind = kind
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
