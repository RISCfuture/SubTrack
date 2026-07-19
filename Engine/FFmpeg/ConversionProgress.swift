import Foundation

/// A point-in-time snapshot of an `ffmpeg` conversion's progress.
public struct ConversionProgress: Sendable, Equatable {

  /**
   Completed fraction in `0...1`, or `nil` when it cannot be computed
   (e.g., the source duration is unknown).
   */
  public var fraction: Double?

  /// The output timestamp reached so far.
  public var outTime: Duration

  /// The encoding speed relative to realtime (e.g., `1.5` = 1.5×), if reported.
  public var speed: Double?

  /// The output size in bytes so far, if reported.
  public var totalSize: Int?

  public init(
    fraction: Double? = nil,
    outTime: Duration = .zero,
    speed: Double? = nil,
    totalSize: Int? = nil
  ) {
    self.fraction = fraction
    self.outTime = outTime
    self.speed = speed
    self.totalSize = totalSize
  }
}
