import Foundation

/**
 A queue item's output file size, together with whether it is still a
 projection rather than a measurement of a file on disk.
 */
public struct OutputSize: Sendable, Equatable {

  /// The size, in bytes.
  public let byteCount: Int

  /// Whether ``byteCount`` is projected rather than measured.
  public let isEstimate: Bool

  public init(byteCount: Int, isEstimate: Bool) {
    self.byteCount = byteCount
    self.isEstimate = isEstimate
  }

  /// A size read off a finished output file.
  public static func measured(_ byteCount: Int) -> Self {
    Self(byteCount: byteCount, isEstimate: false)
  }

  /// A size predicted from planned track drops or from a run still in flight.
  public static func estimated(_ byteCount: Int) -> Self {
    Self(byteCount: byteCount, isEstimate: true)
  }
}
