public import Foundation
public import SwiftData

/**
 The SwiftData persistence record for one named queue: its file list plus the
 per-queue settings (rules, active preset, destination). Modeled CloudKit-ready
 (mirroring ``StoredPreset``): every property has a default and there are no
 unique constraints.

 `sortIndex` orders queues in the sidebar. `rulesData` holds the queue's
 ``SlimRules`` as encoded JSON; `destinationBookmark` is the security-scoped
 output-folder bookmark. Items cascade-delete with the queue.
 */
@Model
public final class StoredQueue {
  /// The queue's stable identity, carried through to its runtime ``QueueCoordinator``.
  public var id = UUID()

  /// The name shown in the sidebar.
  public var name: String = ""

  /// The queue's position in the sidebar.
  public var sortIndex: Int = 0

  /// When the queue was created, which breaks ties between equal sort indices.
  public var createdAt = Date.now

  /// The queue's rules, stored as encoded JSON for forward compatibility.
  public var rulesData = Data()

  /// The preset the queue's rules currently match, or `nil` when they match none.
  public var activePresetID: UUID?

  /// A security-scoped bookmark to the output folder, so it stays writable after a relaunch.
  public var destinationBookmark: Data?

  /**
   The queue's ``OutputNameFormat`` as its raw template text. Empty for
   records written before formats existed, which read back as
   ``OutputNameFormat/slimmed`` — the name those queues already produced.
   */
  public var nameTemplate: String = ""

  /**
   Optional to satisfy CloudKit, which requires every relationship to be
   optional. Treated as an empty list everywhere it's read.
   */
  @Relationship(deleteRule: .cascade, inverse: \StoredQueueItem.queue)
  public var items: [StoredQueueItem]? = []

  /// Creates a record from already-encoded field values, defaulting every one.
  public init(
    id: UUID = UUID(),
    name: String = "",
    sortIndex: Int = 0,
    createdAt: Date = .now,
    rulesData: Data = Data(),
    activePresetID: UUID? = nil,
    destinationBookmark: Data? = nil,
    items: [StoredQueueItem] = []
  ) {
    self.id = id
    self.name = name
    self.sortIndex = sortIndex
    self.createdAt = createdAt
    self.rulesData = rulesData
    self.activePresetID = activePresetID
    self.destinationBookmark = destinationBookmark
    self.items = items
  }
}

extension StoredQueue {

  /**
   The decoded rules (backed by ``rulesData``), falling back to
   ``SlimRules/default`` when the stored blob can't be decoded.
   */
  public var rules: SlimRules {
    get { (try? JSONDecoder().decode(SlimRules.self, from: rulesData)) ?? .default }
    set { rulesData = Self.encode(newValue) }
  }

  /// The decoded output-name format (backed by ``nameTemplate``).
  public var naming: OutputNameFormat {
    get { nameTemplate.isEmpty ? .slimmed : OutputNameFormat(template: nameTemplate) }
    set { nameTemplate = newValue.template }
  }

  /// Creates a record for a named queue, encoding `rules` into ``rulesData``.
  public convenience init(id: UUID = UUID(), name: String, sortIndex: Int = 0, rules: SlimRules) {
    self.init(id: id, name: name, sortIndex: sortIndex, rulesData: Self.encode(rules))
  }

  static func encode(_ rules: SlimRules) -> Data {
    (try? JSONEncoder().encode(rules)) ?? Data()
  }
}

extension StoredQueue {

  /**
   The `Sendable` value projection, with items ordered by their `sortIndex`
   (SwiftData relationships are unordered).
   */
  public var asSnapshot: QueueSnapshot {
    QueueSnapshot(
      id: id,
      name: name,
      sortIndex: sortIndex,
      createdAt: createdAt,
      rules: rules,
      naming: naming,
      activePresetID: activePresetID,
      destinationBookmark: destinationBookmark,
      items: (items ?? []).sorted { $0.sortIndex < $1.sortIndex }.map(\.asSnapshot)
    )
  }

  /// Creates a record holding everything `snapshot` carries, items included.
  public convenience init(snapshot: QueueSnapshot) {
    self.init()
    id = snapshot.id
    name = snapshot.name
    sortIndex = snapshot.sortIndex
    createdAt = snapshot.createdAt
    rules = snapshot.rules
    naming = snapshot.naming
    activePresetID = snapshot.activePresetID
    destinationBookmark = snapshot.destinationBookmark
    items = snapshot.items.map { StoredQueueItem(snapshot: $0) }
  }
}

/**
 A `Sendable`, value-type snapshot of a ``StoredQueue`` and its items — the
 seam the persistence layer uses to map between SwiftData and the runtime.
 */
public struct QueueSnapshot: Sendable, Equatable, Identifiable {
  public let id: UUID
  public var name: String
  public var sortIndex: Int
  public var createdAt: Date
  public var rules: SlimRules
  public var naming: OutputNameFormat
  public var activePresetID: UUID?
  public var destinationBookmark: Data?
  public var items: [QueueItemSnapshot]

  public init(
    id: UUID = UUID(),
    name: String = "",
    sortIndex: Int = 0,
    createdAt: Date = .now,
    rules: SlimRules = .default,
    naming: OutputNameFormat = .slimmed,
    activePresetID: UUID? = nil,
    destinationBookmark: Data? = nil,
    items: [QueueItemSnapshot] = []
  ) {
    self.id = id
    self.name = name
    self.sortIndex = sortIndex
    self.createdAt = createdAt
    self.rules = rules
    self.naming = naming
    self.activePresetID = activePresetID
    self.destinationBookmark = destinationBookmark
    self.items = items
  }
}
