public import Foundation

/**
 A shared, app-wide gate on how many encodes may run at once across every
 queue.

 Each ``QueueCoordinator`` consults the one governor its ``Workspace`` hands
 it — acquiring a slot before starting an item and releasing it when the item
 finishes — so ``limit`` caps concurrency globally rather than per queue.
 Coordinators register a pump callback so a freed slot immediately wakes any
 queue that was waiting on the global limit.

 For as long as any slot is held, the governor also holds one `ProcessInfo`
 activity, so a batch left to run unattended isn't suspended partway through by
 idle sleep. That defers *idle* sleep only: it does nothing against a closed
 lid, an explicit Sleep, or a low-battery sleep.
 */
@MainActor
@Observable
public final class EncodeGovernor {
  /// How many encodes a governor allows at once when the caller doesn't choose.
  nonisolated public static let defaultLimit = 2

  /// The activity's debugging label, as `pmset -g assertions` reports it.
  private static let activityReason = "Encoding queued media"

  /**
   The maximum number of encodes allowed to run simultaneously across all
   queues. Raising it lets waiting coordinators start more work at once.
   */
  public var limit: Int {
    didSet { if limit > oldValue { notifyWaiters() } }
  }

  /// The number of slots currently held by running encodes.
  public private(set) var activeCount = 0

  /// Whether the governor is currently holding off idle sleep.
  public var isHoldingActivity: Bool { activityToken != nil }

  private var waiters: [UUID: @MainActor () -> Void] = [:]

  @ObservationIgnored private var activityToken: (any NSObjectProtocol)?

  /// Creates a governor capping concurrent encodes at `limit` across every queue.
  public init(limit: Int = EncodeGovernor.defaultLimit) {
    self.limit = limit
  }

  /// Claims a slot when one is free, reporting whether the caller may start.
  func acquire() -> Bool {
    guard activeCount < limit else { return false }
    activeCount += 1
    if activeCount == 1 { beginIdleSleepAssertion() }
    return true
  }

  /// Frees a previously-claimed slot and wakes waiting coordinators.
  func release() {
    if activeCount > 0 {
      activeCount -= 1
      if activeCount == 0 { endIdleSleepAssertion() }
    }
    notifyWaiters()
  }

  /**
   Registers a coordinator's pump, invoked when a slot frees so it can start
   work that was waiting on the global limit.
   */
  func register(_ id: UUID, pump: @escaping @MainActor () -> Void) {
    waiters[id] = pump
  }

  /// Drops a torn-down coordinator's pump.
  func unregister(_ id: UUID) {
    waiters[id] = nil
  }

  private func notifyWaiters() {
    for pump in waiters.values { pump() }
  }

  /**
   Takes the activity that holds off idle sleep. `.userInitiated` already
   contains `NSActivityIdleSystemSleepDisabled`, so naming further options
   would ask for nothing more.
   */
  private func beginIdleSleepAssertion() {
    activityToken = ProcessInfo.processInfo.beginActivity(
      options: .userInitiated,
      reason: Self.activityReason
    )
  }

  private func endIdleSleepAssertion() {
    guard let activityToken else { return }
    ProcessInfo.processInfo.endActivity(activityToken)
    self.activityToken = nil
  }
}
