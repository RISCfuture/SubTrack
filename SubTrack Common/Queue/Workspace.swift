import Foundation

/// A queue's rolled-up state, surfaced as the sidebar's per-queue icon.
public enum QueueAggregateStatus: Sendable, Equatable {
  /// Nothing queued, or everything settled without encoding or attention.
  case idle
  /// One or more items are probing or encoding; carries overall progress (`0...1`).
  case running(Double)
  /// At least one item is missing, failed, or incompatible.
  case attention
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

  private let coordinatorFactory: @MainActor (UUID, String, Int) -> QueueCoordinator

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
   */
  public init(makeCoordinator: @escaping @MainActor (UUID, String, Int) -> QueueCoordinator) {
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
   Builds a coordinator for a queue and appends it in sidebar order, without
   persisting — the shared entry point for both launch hydration and
   ``newQueue(name:)``.
   */
  @discardableResult
  public func makeCoordinator(id: UUID = UUID(), name: String, sortIndex: Int) -> QueueCoordinator {
    let coordinator = coordinatorFactory(id, name, sortIndex)
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
}
