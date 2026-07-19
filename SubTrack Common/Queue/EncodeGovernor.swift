import Foundation

/**
 A shared, app-wide gate on how many encodes may run at once across every
 queue.

 Each ``QueueCoordinator`` consults the one governor its ``Workspace`` hands
 it — acquiring a slot before starting an item and releasing it when the item
 finishes — so ``limit`` caps concurrency globally rather than per queue.
 Coordinators register a pump callback so a freed slot immediately wakes any
 queue that was waiting on the global limit.
 */
@MainActor
@Observable
public final class EncodeGovernor {
  /// How many encodes a governor allows at once when the caller doesn't choose.
  nonisolated public static let defaultLimit = 2

  /**
   The maximum number of encodes allowed to run simultaneously across all
   queues. Raising it lets waiting coordinators start more work at once.
   */
  public var limit: Int {
    didSet { if limit > oldValue { notifyWaiters() } }
  }

  /// The number of slots currently held by running encodes.
  public private(set) var activeCount = 0

  private var waiters: [UUID: @MainActor () -> Void] = [:]

  /// Creates a governor capping concurrent encodes at `limit` across every queue.
  public init(limit: Int = EncodeGovernor.defaultLimit) {
    self.limit = limit
  }

  /// Claims a slot when one is free, reporting whether the caller may start.
  func acquire() -> Bool {
    guard activeCount < limit else { return false }
    activeCount += 1
    return true
  }

  /// Frees a previously-claimed slot and wakes waiting coordinators.
  func release() {
    if activeCount > 0 { activeCount -= 1 }
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
}
