import AppKit
import Foundation
public import SwiftData
import os

/**
 Bridges the runtime ``Workspace`` and its SwiftData store: hydrates queues on
 launch and writes structural and settled changes back through.

 Modeled on ``PresetStore`` — a `@MainActor` wrapper over a `ModelContext`
 that filters and sorts in memory (never `#Predicate` over a `UUID`). Live
 `progress` never reaches here: coordinators fire ``QueueCoordinator/onPersistableChange``
 only on item add/remove/reorder and settled status transitions, and the
 workspace fires ``Workspace/onWorkspaceChange`` on queue-level edits.
 */
@MainActor
public final class QueuePersistenceController {

  /**
   How long a queue may sit dirty before it is written. Adding a folder of
   files settles one item at a time, and each settling would otherwise cost a
   write of the whole queue — so a hundred-file add costs a hundred writes of a
   hundred items. Collecting the settlings that land inside this window turns
   that back into a handful of writes without letting any change sit unwritten
   for long enough to notice.
   */
  private static let writeInterval = Duration.milliseconds(200)

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SubTrack",
    category: "persistence"
  )

  #if DEBUG
    /**
     Makes every read of the store fail, so a test can drive the paths that
     refuse to treat an unreadable store as an empty one. Compiled out of
     release builds; see ``UITestHarness``.
     */
    public var failsFetchesForTesting = false

    /// Makes every write fail, the read-side counterpart of ``failsFetchesForTesting``.
    public var failsWritesForTesting = false
  #endif

  private let modelContext: ModelContext
  private let workspace: Workspace
  private let health: PersistenceHealth

  /// Queues changed since the last write, and the task that will write them.
  private var dirtyQueueIDs: Set<UUID> = []
  private var scheduledWrite: Task<Void, Never>?

  /**
   The flush-at-termination observer, held so it is registered only once and
   can be removed. It refers to the controller weakly and lives as long as the
   process, which is exactly as long as the controller it serves.
   */
  private var terminationObserver: (any NSObjectProtocol)?

  /**
   Creates a controller that reads and writes `workspace`'s queues through
   `modelContext`. Nothing is loaded until ``load()`` runs.

   - Parameter modelContext: The context holding the queue records.
   - Parameter workspace: The live queues this controller hydrates and writes
     back.
   - Parameter health: Where this controller reports whether the store is
     readable and writable. Defaults to a record of its own, which is what a
     test that isn't asking the question wants.
   */
  public init(
    modelContext: ModelContext,
    workspace: Workspace,
    health: PersistenceHealth = PersistenceHealth()
  ) {
    self.modelContext = modelContext
    self.workspace = workspace
    self.health = health
  }

  // MARK: - Launch hydration

  /**
   Rebuilds the workspace from the store, or seeds one empty queue when the
   store is empty, then wires write-through and kicks each queue's post-load
   reconciliation (re-probe, revalidate, re-resolve sources).
   */
  public func load() {
    let stored: [StoredQueue]
    do {
      stored = try fetchAll()
    } catch {
      // A transient fetch failure is not an empty store: seeding and writing
      // through here would overwrite the user's real queues. Present an
      // in-memory queue for this session without wiring write-through, leaving
      // the on-disk data intact for a later, healthy launch. Nothing clears the
      // condition ``fetchAll()`` just recorded, because with write-through
      // unwired there is no later write to succeed — which is the truth of it.
      workspace.makeCoordinator(name: Workspace.seedQueueName, sortIndex: 0)
      workspace.selectFirstIfNeeded()
      return
    }
    let sorted = stored.sorted { $0.sortIndex < $1.sortIndex }
    if sorted.isEmpty {
      workspace.makeCoordinator(name: Workspace.seedQueueName, sortIndex: 0)
    } else {
      for snapshot in sorted.map(\.asSnapshot) {
        let coordinator = workspace.makeCoordinator(
          id: snapshot.id,
          name: snapshot.name,
          sortIndex: snapshot.sortIndex
        )
        coordinator.hydrate(snapshot)
      }
    }
    workspace.selectFirstIfNeeded()
    for coordinator in workspace.coordinators { coordinator.postHydrationRefresh() }
    wireHooks()
    persistAll()
  }

  // MARK: - Write-through

  /**
   Reconciles the whole workspace: deletes queues no longer present, upserts
   the rest (reindexing `sortIndex`), and saves.

   A store that cannot be read is left entirely alone. Reconciling against
   records that failed to arrive would read as "every stored queue has been
   deleted" and as "no queue has a record yet", so it would delete the user's
   queues and then write duplicates of them back.
   */
  public func persistAll() {
    guard let records = try? fetchAll() else { return }
    dirtyQueueIDs.removeAll()
    let liveIDs = Set(workspace.coordinators.map(\.id))
    for record in records where !liveIDs.contains(record.id) {
      modelContext.delete(record)
    }
    for coordinator in workspace.coordinators { upsert(coordinator.snapshot, into: records) }
    save()
  }

  /**
   Writes every queue left dirty by a change still inside its write window.
   Called on the timer, and directly at termination so a change made in the
   last moments of a session isn't lost with the process.

   Queues stay dirty when the store can't be read, so the next write window
   tries them again rather than dropping the changes on the floor.
   */
  public func flushPendingWrites() {
    scheduledWrite?.cancel()
    scheduledWrite = nil
    guard !dirtyQueueIDs.isEmpty else { return }
    guard let records = try? fetchAll() else { return }
    let ids = dirtyQueueIDs
    dirtyQueueIDs.removeAll()
    for coordinator in workspace.coordinators where ids.contains(coordinator.id) {
      upsert(coordinator.snapshot, into: records)
    }
    save()
  }

  // MARK: - Wiring

  private func wireHooks() {
    for coordinator in workspace.coordinators { wire(coordinator) }
    workspace.onCoordinatorCreated = { [weak self] in self?.wire($0) }
    // A queue being added, removed, or renamed is both rare and structural, so it
    // reconciles the whole workspace immediately rather than waiting on the timer.
    workspace.onWorkspaceChange = { [weak self] in self?.persistAll() }
    observeTermination()
  }

  private func wire(_ coordinator: QueueCoordinator) {
    coordinator.onPersistableChange = { [weak self, weak coordinator] in
      guard let self, let coordinator else { return }
      self.markDirty(coordinator.id)
    }
  }

  /**
   Notes that `id` needs writing and starts the window it will be written at
   the end of, if one isn't already open.

   The waiting task holds the controller strongly, so a change made moments
   before the last reference to the controller goes away is still written
   rather than lost with it. The reference lasts one write interval: the task
   clears itself as it finishes, breaking the cycle.
   */
  private func markDirty(_ id: UUID) {
    dirtyQueueIDs.insert(id)
    guard scheduledWrite == nil else { return }
    scheduledWrite = Task {
      try? await Task.sleep(for: Self.writeInterval)
      guard !Task.isCancelled else { return }
      self.scheduledWrite = nil
      self.flushPendingWrites()
    }
  }

  private func observeTermination() {
    guard terminationObserver == nil else { return }
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.flushPendingWrites() }
    }
  }

  // MARK: - Mapping

  /**
   Writes one queue into `records`' matching row, inserting one when the queue
   has never been stored.

   The rows are handed in rather than fetched per queue: one read for a whole
   reconciliation instead of one per queue, and — more to the point — a read
   that has already been checked, so a failure can never be mistaken here for
   "this queue has no record yet" and answered with a duplicate row.
   */
  private func upsert(_ snapshot: QueueSnapshot, into records: [StoredQueue]) {
    let record =
      records.first { $0.id == snapshot.id }
      ?? insertQueue(id: snapshot.id, createdAt: snapshot.createdAt)
    record.name = snapshot.name
    record.sortIndex = snapshot.sortIndex
    record.rules = snapshot.rules
    record.activePresetID = snapshot.activePresetID
    record.destinationBookmark = snapshot.destinationBookmark
    reconcileItems(of: record, to: snapshot.items)
  }

  /**
   Upserts each item by `id`, preserving `sortIndex` order and deleting rows
   dropped from the queue.
   */
  private func reconcileItems(of record: StoredQueue, to snapshots: [QueueItemSnapshot]) {
    var orphans = Dictionary(
      (record.items ?? []).map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var ordered: [StoredQueueItem] = []
    for snapshot in snapshots {
      if let existing = orphans.removeValue(forKey: snapshot.id) {
        existing.apply(snapshot)
        ordered.append(existing)
      } else {
        let inserted = StoredQueueItem(snapshot: snapshot)
        modelContext.insert(inserted)
        ordered.append(inserted)
      }
    }
    for orphan in orphans.values { modelContext.delete(orphan) }
    record.items = ordered
  }

  private func insertQueue(id: UUID, createdAt: Date) -> StoredQueue {
    let record = StoredQueue()
    record.id = id
    record.createdAt = createdAt
    modelContext.insert(record)
    return record
  }

  /**
   Every stored queue. Throwing rather than falling back to an empty array:
   the callers each have a different right answer to an unreadable store, and
   none of them is "there are no queues".
   */
  private func fetchAll() throws -> [StoredQueue] {
    do {
      #if DEBUG
        // A Cocoa error, not a `PersistenceError`: this stands in for what the
        // store itself would throw, and the catch below is what turns it into
        // one. Throwing the wrapper here would have it wrapped a second time.
        if failsFetchesForTesting { throw CocoaError(.fileReadUnknown) }
      #endif
      // Small set; filtering in memory avoids a SwiftData `#Predicate` over UUID.
      return try modelContext.fetch(FetchDescriptor<StoredQueue>())
    } catch {
      report(.fetchFailed(detail: String(describing: error)))
      throw error
    }
  }

  private func save() {
    do {
      #if DEBUG
        if failsWritesForTesting { throw CocoaError(.fileWriteUnknown) }
      #endif
      try modelContext.save()
      health.recordSuccess(from: .queues)
    } catch {
      report(.saveFailed(detail: String(describing: error)))
    }
  }

  /// Logs a failure and raises it as the condition the status bar reports.
  private func report(_ failure: PersistenceError) {
    Self.logger.error("\(failure.userMessage, privacy: .public)")
    health.record(failure, from: .queues)
  }
}
