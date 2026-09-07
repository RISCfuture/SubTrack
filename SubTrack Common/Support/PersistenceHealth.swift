public import Observation

/**
 Whether SubTrack is managing to record the user's work.

 A failed write is a *condition, not an event*: it stays true until a write
 succeeds, it can repeat every few seconds, and the user did nothing to cause
 it. That rules out an alert — one per failed write would be intolerable, and
 one for the first failure only is worse, because dismissing it hides a
 problem that is still true. So the failure is held here and the interface
 reads it, showing nothing at all while every store is healthy.

 Failures are kept per store rather than in one slot. The queue autosaves
 every couple of hundred milliseconds while files are being added, so a single
 shared slot would let the queue's next successful write clear a preset
 failure that is still true, and the other way about.
 */
@MainActor
@Observable
public final class PersistenceHealth {

  private var failures: [Source: PersistenceError] = [:]

  /// Every store currently failing, the queues first.
  public var activeFailures: [PersistenceError] {
    Source.allCases.compactMap { failures[$0] }
  }

  /**
   The failure to report, or `nil` while every store is healthy — which is the
   overwhelmingly common case, and the one that must cost the interface
   nothing.
   */
  public var failure: PersistenceError? { activeFailures.first }

  /**
   Fired when a store's failure state changes — raised or cleared — and never
   on a repeat, so a store failing on every write announces itself once. A
   closure rather than a reference, so this stays free of any knowledge of what
   listens and a listener that also writes cannot form a cycle back into here.
   */
  @ObservationIgnored public var onConditionChanged: @MainActor (PersistenceError?) -> Void = { _ in
  }

  /// Creates a health record with every store healthy.
  public init() {}

  /**
   Notes that `source` could not be read or written.

   Silent when the same failure is already recorded, so a store failing on
   every write in a tight loop invalidates the views watching it once rather
   than once per attempt.
   */
  func record(_ failure: PersistenceError, from source: Source) {
    guard failures[source] != failure else { return }
    failures[source] = failure
    onConditionChanged(failure)
  }

  /// Notes that `source` has written successfully, clearing any failure it held.
  func recordSuccess(from source: Source) {
    guard failures[source] != nil else { return }
    failures[source] = nil
    onConditionChanged(nil)
  }

  /// Which of the app's stores a failure came from.
  public enum Source: Sendable, CaseIterable {

    /// The queues and their items.
    case queues

    /// The saved rule presets.
    case presets
  }
}
