public import Foundation

/// A queue's rolled-up state, surfaced as the sidebar's per-queue icon.
public enum QueueAggregateStatus: Sendable, Equatable {
  /// Nothing queued, or everything settled without encoding or attention.
  case idle
  /// One or more items are probing or encoding; carries overall progress (`0...1`).
  case running(Double)
  /**
   At least one item is missing, failed, or incompatible; carries the loudest
   tier among them, so a queue holding a failed run does not read as mildly as
   one holding only a plan the build can't perform.
   */
  case attention(Severity)
  /// Every item finished successfully.
  case done
}

/**
 Owns the app's live queues: one ``QueueCoordinator`` per queue plus the
 current selection, all sharing a single engine and ``EncodeGovernor``.

 The runtime seam behind ``AppEnvironment``: the persistence layer builds
 coordinators through ``makeCoordinator(id:name:sortIndex:)`` during launch
 hydration, and the sidebar's add, rename, delete, and selection commands
 drive ``newQueue(name:)``, ``renameQueue(_:to:)``, ``deleteQueue(_:)``, and
 ``selectQueue(_:)``. ``onWorkspaceChange`` fires on queue-level structural
 edits so the controller writes them through.
 */
@MainActor
@Observable
public final class Workspace {
  /// The default name for the queue seeded on first launch (`Queue 1`).
  public static let seedQueueName = defaultQueueName(existingNames: [])

  /// The live queues, in sidebar order.
  public private(set) var coordinators: [QueueCoordinator] = []

  /// The selected queue's identity; runtime-only (not persisted).
  public var selectedQueueID: UUID?

  /**
   Fired when a queue is added, renamed, deleted, or reordered so the
   persistence layer can write the workspace through.
   */
  public var onWorkspaceChange: @MainActor () -> Void = {}

  /**
   Fired for each coordinator the moment it's created (during launch
   hydration or ``newQueue(name:)``) so the persistence layer can wire its
   write-through hook.
   */
  public var onCoordinatorCreated: @MainActor (QueueCoordinator) -> Void = { _ in }

  /**
   The undo manager of the window the queues are shown in, or `nil` before one
   has appeared. Handed to every queue — the ones already here and every one
   made later — so a destructive edit can be taken back however it was made.

   The fan-out is not redundant with the assignment in
   ``makeCoordinator(id:name:sortIndex:)``: launch hydration builds every
   persisted queue long before there is a window to ask.
   */
  @ObservationIgnored public weak var undoManager: UndoManager? {
    didSet {
      for coordinator in coordinators { coordinator.undoManager = undoManager }
    }
  }

  private let coordinatorFactory: @MainActor (UUID, String, Int) -> QueueCoordinator

  /// Told when the app starts and stops encoding, or `nil` when nothing is listening.
  private let reporter: (any QueueCompletionReporting)?

  /// Where the run's edges and its files' troubles are written down, if anywhere.
  private let log: ActivityLog?

  /// Whether any queue was encoding the last time the workspace looked.
  @ObservationIgnored private var runIsInFlight = false

  /// What the run in progress has come to so far.
  @ObservationIgnored private var tally = RunTally()

  /**
   The selected queue's coordinator, falling back to the first when the
   selection is stale. The workspace always holds at least one queue after
   launch hydration, so this is the valid target for `AppEnvironment.queue`.
   */
  public var selectedCoordinator: QueueCoordinator {
    coordinators.first { $0.id == selectedQueueID } ?? coordinators[0]
  }

  /**
   How far the app's work as a whole has got (`0...1`), or `nil` when no queue
   is doing anything — the value the Dock icon reflects, so it spans every
   queue rather than the one that happens to be selected.

   Weighted per item rather than per queue, so a fifty-file queue counts for
   fifty times what a one-file queue does.
   */
  public var dockProgress: Double? {
    let items = coordinators.flatMap(\.items)
    guard items.contains(where: \.status.isActive) else { return nil }
    return items.reduce(0.0) { $0 + $1.progressWeight } / Double(items.count)
  }

  private var selectedCoordinatorIsMissing: Bool {
    guard let selectedQueueID else { return true }
    return !coordinators.contains { $0.id == selectedQueueID }
  }

  /**
   Creates a workspace whose queues are built by `makeCoordinator`, which
   wires each new coordinator to the shared engine, governor, and access
   closures.

   - Parameter reporter: Told when the app's encoding starts and stops. Leaving
     it `nil` — every preview, UI test, and unit test — runs the queues with
     nothing listening.
   - Parameter log: Keeps the account of what a run came to and what went wrong
     in it. `nil` runs the queues without one.
   - Parameter makeCoordinator: Builds a queue's coordinator from its identity,
     name, and sidebar position.
   */
  public init(
    reporting reporter: (any QueueCompletionReporting)? = nil,
    logging log: ActivityLog? = nil,
    makeCoordinator: @escaping @MainActor (UUID, String, Int) -> QueueCoordinator
  ) {
    self.reporter = reporter
    self.log = log
    self.coordinatorFactory = makeCoordinator
  }

  /// The lowest-numbered `Queue N` name not already in `existingNames`.
  public static func defaultQueueName(existingNames: some Sequence<String>) -> String {
    let used = Set(existingNames)
    var number = 1
    while used.contains(String(localized: "Queue \(number, format: .number)", bundle: #bundle)) {
      number += 1
    }
    return String(localized: "Queue \(number, format: .number)", bundle: #bundle)
  }

  /**
   How a run's line names the queues it touched: the one, or how many when it
   spanned several. Never "all of them" — a run is app-wide in the sense that
   the concurrency limit is, not in the sense that it concerns every queue, and
   a workspace holding three queues while one of them runs must not read as
   though all three had been busy.
   */
  private static func scope(of queueNames: Set<String>) -> String {
    guard queueNames.count != 1 else { return queueNames.first ?? "" }
    return String(localized: "\(queueNames.count, format: .number) queues", bundle: #bundle)
  }

  /**
   Builds a coordinator for a queue and appends it in sidebar order, without
   persisting — the shared entry point for both launch hydration and
   ``newQueue(name:)``.
   */
  @discardableResult
  public func makeCoordinator(id: UUID = UUID(), name: String, sortIndex: Int) -> QueueCoordinator {
    let coordinator = coordinatorFactory(id, name, sortIndex)
    // The one place every coordinator is created, so the run hooks are wired
    // here rather than through `onCoordinatorCreated`, which the persistence
    // layer already owns. Wired for every queue rather than only when a notifier
    // is listening: the run's edges are what the log is built on, and gating
    // them on the notifier left the whole path dead in every preview, UI test
    // and unit test — which is why nothing about it could be tested.
    coordinator.onEncodeActivityChanged = { [weak self] in self?.updateRunActivity() }
    coordinator.onRunSettled = { [weak self, weak coordinator] outcome in
      guard let self, let coordinator else { return }
      self.tally.record(outcome, from: coordinator.name)
    }
    coordinator.onItemSettled = { [weak self, weak coordinator] item, state in
      guard let self, let coordinator else { return }
      self.log?.recordSettled(
        state,
        itemID: item.id,
        fileName: item.displayName,
        queueName: coordinator.name
      )
    }
    // Unconditional, unlike the run hooks above: an undo is a UI event, not
    // something a run reports, and a workspace with no reporter still has a
    // sidebar the user is looking at.
    coordinator.undoManager = undoManager
    coordinator.onUndoAppliedChange = { [weak self, weak coordinator] in
      guard let coordinator else { return }
      self?.selectQueue(coordinator.id)
    }
    coordinators.append(coordinator)
    onCoordinatorCreated(coordinator)
    return coordinator
  }

  /**
   The next unused `Queue N` name, so a queue added from the sidebar or the
   File menu never collides with an existing one even after deletions.
   */
  public func nextQueueName() -> String {
    Self.defaultQueueName(existingNames: coordinators.map(\.name))
  }

  /// Adds a new empty queue, selects it, and writes the workspace through.
  @discardableResult
  public func newQueue(name: String) -> QueueCoordinator {
    let coordinator = makeCoordinator(name: name, sortIndex: coordinators.count)
    selectedQueueID = coordinator.id
    onWorkspaceChange()
    return coordinator
  }

  /// Renames a queue and writes the change through.
  public func renameQueue(_ id: UUID, to name: String) {
    guard let coordinator = coordinators.first(where: { $0.id == id }) else { return }
    coordinator.name = name
    onWorkspaceChange()
  }

  /**
   Cancels and tears down a queue, then removes it. Reselects a sibling and
   re-seeds an empty "Queue 1" when the last queue is deleted so the workspace
   is never empty. Writes the change through.
   */
  public func deleteQueue(_ id: UUID) {
    guard let index = coordinators.firstIndex(where: { $0.id == id }) else { return }
    // Unwired before teardown, because the runs `teardown` cancels go on firing
    // their hooks as they unwind: a queue the workspace can no longer see must
    // neither report into the run nor claim to have ended it.
    coordinators[index].onEncodeActivityChanged = {}
    coordinators[index].onRunSettled = { _ in }
    coordinators[index].teardown()
    coordinators.remove(at: index)
    reindex()
    if coordinators.isEmpty {
      makeCoordinator(name: Self.seedQueueName, sortIndex: 0)
    }
    if selectedQueueID == id {
      selectedQueueID = coordinators.first?.id
    }
    onWorkspaceChange()
    abandonRunIfEnded()
  }

  /// Selects a queue (runtime-only; not persisted).
  public func selectQueue(_ id: UUID) {
    guard coordinators.contains(where: { $0.id == id }) else { return }
    selectedQueueID = id
  }

  /// Selects the first queue when nothing valid is selected.
  public func selectFirstIfNeeded() {
    if selectedCoordinatorIsMissing { selectedQueueID = coordinators.first?.id }
  }

  /// Renumbers `sortIndex` to match sidebar order after a structural change.
  private func reindex() {
    for (offset, coordinator) in coordinators.enumerated() { coordinator.sortIndex = offset }
  }

  /**
   Reports the edges of a run: the moment the app starts encoding, and the
   moment the last queue stops.

   Every queue's activity hook lands here, so a run spanning several queues
   announces itself once rather than once per queue. A run the user broke off —
   cancelled, or its items removed mid-run — passes without a word.
   */
  private func updateRunActivity() {
    let isInFlight = coordinators.contains(where: \.hasEncodeWorkInFlight)
    guard isInFlight != runIsInFlight else { return }
    runIsInFlight = isInFlight

    if isInFlight {
      tally = RunTally()
      for coordinator in coordinators where coordinator.hasEncodeWorkInFlight {
        tally.noteParticipant(coordinator.name)
      }
      log?.recordRunStarted(in: Self.scope(of: tally.queueNames))
      reporter?.queueWorkDidBegin()
    } else {
      recordRunFinished()
      // The notification's rule, not the log's: a run the user broke off is one
      // they were there for, and needs no announcement.
      if tally.isWorthReporting { reporter?.queueWorkDidFinish(tally.summary) }
    }
  }

  /// Writes down what the run came to, however it ended.
  private func recordRunFinished() {
    let summary = tally.summary
    log?.recordRunFinished(
      encoded: summary.finishedCount,
      failed: summary.failedCount,
      cancelled: summary.cancelledCount,
      bytesSaved: summary.bytesSaved,
      in: Self.scope(of: tally.queueNames)
    )
  }

  /**
   Forgets a run that a deleted queue has just ended, so tearing down the only
   working queue never reports a completion the user didn't wait for. A run
   still alive in a surviving queue is left to finish and report normally.
   */
  private func abandonRunIfEnded() {
    guard !coordinators.contains(where: \.hasEncodeWorkInFlight) else { return }
    // The log still closes its line: the run did happen, and a reader looking
    // for what became of it should not find a beginning with no end.
    if runIsInFlight { recordRunFinished() }
    runIsInFlight = false
    tally = RunTally()
  }

  /// Accumulates what a run comes to, one settled item at a time.
  private struct RunTally {
    private(set) var finishedCount = 0
    private(set) var failedCount = 0
    private(set) var cancelledCount = 0
    private(set) var bytesSaved: Int?
    private(set) var outputURLs: [URL] = []

    /**
     The queues this run has touched. A run is app-wide because the concurrency
     limit is, but it is not therefore about every queue — so its lines name the
     ones that actually took part rather than claiming the lot.
     */
    private(set) var queueNames: Set<String> = []

    /// What to report, once the run has ended.
    var summary: QueueRunSummary {
      .init(
        finishedCount: finishedCount,
        failedCount: failedCount,
        cancelledCount: cancelledCount,
        bytesSaved: bytesSaved,
        outputURLs: outputURLs
      )
    }

    /**
     Whether the run came to anything worth telling the user about.

     A run the user broke off says nothing, however many files it got through
     first: the notification is for a run you walked away from, and whoever
     stopped this one was there to stop it.
     */
    var isWorthReporting: Bool { cancelledCount == 0 && finishedCount + failedCount > 0 }

    /**
     Folds one settled run in. Savings are summed signed, so a track that had
     to be transcoded larger tells against the total honestly instead of being
     rounded away item by item.
     */
    /// Notes a queue as taking part before any of its files have settled.
    mutating func noteParticipant(_ queueName: String) { queueNames.insert(queueName) }

    mutating func record(_ outcome: QueueRunOutcome, from queueName: String) {
      queueNames.insert(queueName)
      switch outcome.result {
        case .finished: finishedCount += 1
        case .failed: failedCount += 1
        case .cancelled: cancelledCount += 1
      }
      if let saved = outcome.bytesSaved { bytesSaved = (bytesSaved ?? 0) + saved }
      if let outputURL = outcome.outputURL { outputURLs.append(outputURL) }
    }
  }
}
