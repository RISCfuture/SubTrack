import Foundation

/**
 The live state of an in-flight ingest, driving the progress sheet.

 Two phases, because they measure different things: walking the dropped
 folders has no known total until it ends, while adding what the walk found
 does.
 */
@MainActor
@Observable
public final class IngestProgress {

  /// Which half of the ingest is running: walking the drop, or adding what it found.
  public private(set) var phase: Phase = .scanning

  /// Files finished so far in the current phase.
  public private(set) var completed = 0

  /// How many files the current phase covers, or `nil` while scanning.
  public private(set) var total: Int?

  /// The file being handled, shown beneath the bar.
  public private(set) var currentName: String?

  /**
   Set when the user cancels. The ingest stops at its next chunk boundary,
   keeping whatever it has already added.
   */
  public private(set) var isCancelled = false

  /**
   How far the current phase has got, or `nil` when the total isn't known yet
   so the bar can run indeterminate.
   */
  public var fraction: Double? {
    guard let total, total > 0 else { return nil }
    return Double(completed) / Double(total)
  }

  /// Creates a progress object in its scanning phase, with nothing counted yet.
  public init() {}

  /// Asks the ingest to stop at its next chunk boundary.
  public func cancel() { isCancelled = true }

  func beginScanning() {
    phase = .scanning
    completed = 0
    total = nil
    currentName = nil
  }

  func recordScanned(_ count: Int) {
    completed = count
  }

  func beginAdding(total: Int) {
    phase = .adding
    completed = 0
    self.total = total
  }

  func recordAdded(_ name: String) {
    completed += 1
    currentName = name
  }

  /// Which half of the work is running.
  public enum Phase: Sendable {
    /// Walking the dropped folders for movie files.
    case scanning
    /// Adding the files the walk found to the queue.
    case adding
  }
}
