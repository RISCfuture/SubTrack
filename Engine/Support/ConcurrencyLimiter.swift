import Foundation

/**
 Bounds how many tasks may perform a piece of work at the same time.

 Callers wrap the work in ``withSlot(_:)``, which suspends until a slot is free
 and gives the slot back however the work ends. The limiter gates *admission*
 rather than execution: bodies run off the limiter's own executor, so several may
 be in flight at once, just never more than `limit` of them. That is the
 difference between this and simply putting the work on an actor, whose serial
 executor would admit exactly one.

 A freed slot is handed straight to the longest-waiting task. A task cancelled
 while it waits gives its place up rather than holding the queue behind it, and
 ``withSlot(_:)`` throws `CancellationError` without running the body.
 */
actor ConcurrencyLimiter {
  private let limit: UInt
  private var active: UInt = 0
  private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

  /**
   Waiters cancelled between asking for a slot and parking on one, so the
   parking step can bail out instead of suspending on a continuation that
   nothing is left to resume.
   */
  private var cancelledBeforeParking: Set<UUID> = []

  init(limit: UInt) {
    precondition(limit > 0, "A concurrency limit must admit at least one task")
    self.limit = limit
  }

  /// Runs `body` once a slot is free, releasing the slot when it returns or throws.
  nonisolated func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
    try await acquire()
    do {
      let value = try await body()
      await release()
      return value
    } catch {
      await release()
      throw error
    }
  }

  private func acquire() async throws {
    try Task.checkCancellation()
    guard active >= limit else {
      active += 1
      return
    }

    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if cancelledBeforeParking.remove(id) != nil {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters.append((id, continuation))
        }
      }
    } onCancel: {
      Task { await self.giveUpPlace(of: id) }
    }
  }

  /**
   Hands the slot to whoever has waited longest, or gives it back to the pool
   when nobody is waiting. The count is left untouched when a waiter is woken:
   the slot passes from one holder to the next rather than being freed.
   */
  private func release() {
    guard !waiters.isEmpty else {
      if active > 0 { active -= 1 }
      return
    }
    waiters.removeFirst().continuation.resume()
  }

  private func giveUpPlace(of id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else {
      cancelledBeforeParking.insert(id)
      return
    }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}
