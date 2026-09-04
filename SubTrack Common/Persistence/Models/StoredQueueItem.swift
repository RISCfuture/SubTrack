public import Foundation
public import SwiftData

/**
 The SwiftData persistence record for one file in a ``StoredQueue``. Modeled
 CloudKit-ready (mirroring ``StoredPreset``): every property has a default and
 there are no unique constraints.

 `sortIndex` carries the explicit run order because SwiftData relationships are
 unordered. `sourceBookmark` and `outputFolderBookmark` hold security-scoped
 bookmarks to the source file and to the folder its output is written into, so
 both reads and writes survive relaunch; `sourcePath` is the display identity
 when the source is missing. The persisted status is the settled subset in
 ``PersistedItemStatus``.
 */
@Model
public final class StoredQueueItem {
  /// The item's stable identity, carried through to its runtime `QueueItem`.
  public var id = UUID()

  /// The item's position in the queue's run order.
  public var sortIndex: Int = 0

  /// The source file's path, which stays the item's display identity when the file is gone.
  public var sourcePath: String = ""

  /// A security-scoped bookmark to the source file, so it can be read after a relaunch.
  public var sourceBookmark: Data?

  /// The path this item's slimmed output is written to.
  public var outputPath: String = ""

  /**
   The base name the user gave this one file, or `""` when the queue's name
   format names it — the same empty-means-default convention as
   ``StoredQueue/nameTemplate``. Read through ``customName``.
   */
  public var customNameBase: String = ""
  /// A security-scoped bookmark to the output's folder, so it stays writable after a relaunch.
  public var outputFolderBookmark: Data?

  /// The settled ``PersistedItemStatus`` this item was last saved in, as its raw value.
  public var persistedStatusRaw: String = PersistedItemStatus.ready.rawValue

  /// Why a failed or incompatible item is in that state; `nil` for every other status.
  public var lastError: String?

  /**
   The per-file ``FileTrackSelection`` override, stored as encoded JSON for
   forward compatibility; `nil` when the queue's global rules apply.
   */
  public var selectionData: Data?

  /// The source file's size on disk when it was added; `nil` when it couldn't be stat-ed.
  public var sourceByteCount: Int?

  /**
   The output size and dropped-track count captured when a `.done` item
   finished; `nil` for items that haven't completed.
   */
  public var outputByteCount: Int?

  /// How many tracks the finished run dropped; `nil` for items that haven't completed.
  public var tracksRemoved: Int?

  /// The owning queue (the inverse of ``StoredQueue/items``).
  public var queue: StoredQueue?

  /// Creates a record from already-encoded field values, defaulting every one.
  public init(
    id: UUID = UUID(),
    sortIndex: Int = 0,
    sourcePath: String = "",
    sourceBookmark: Data? = nil,
    outputPath: String = "",
    customNameBase: String = "",
    outputFolderBookmark: Data? = nil,
    persistedStatusRaw: String = PersistedItemStatus.ready.rawValue,
    lastError: String? = nil,
    selectionData: Data? = nil,
    sourceByteCount: Int? = nil,
    outputByteCount: Int? = nil,
    tracksRemoved: Int? = nil
  ) {
    self.id = id
    self.sortIndex = sortIndex
    self.sourcePath = sourcePath
    self.sourceBookmark = sourceBookmark
    self.outputPath = outputPath
    self.customNameBase = customNameBase
    self.outputFolderBookmark = outputFolderBookmark
    self.persistedStatusRaw = persistedStatusRaw
    self.lastError = lastError
    self.selectionData = selectionData
    self.sourceByteCount = sourceByteCount
    self.outputByteCount = outputByteCount
    self.tracksRemoved = tracksRemoved
  }
}

extension StoredQueueItem {

  /**
   The base name the user gave this one file (backed by ``customNameBase``),
   or `nil` when the queue's name format names it.
   */
  public var customName: String? {
    get { customNameBase.isEmpty ? nil : customNameBase }
    set { customNameBase = newValue ?? "" }
  }

  /**
   The decoded per-file selection (backed by ``selectionData``). Decoding
   failure falls back to `nil` so a forward-incompatible blob degrades to
   "use the global rules" rather than crashing.
   */
  public var selection: FileTrackSelection? {
    get {
      guard let selectionData else { return nil }
      return try? JSONDecoder().decode(FileTrackSelection.self, from: selectionData)
    }
    set { selectionData = newValue.flatMap { try? JSONEncoder().encode($0) } }
  }

  /**
   The settled status (backed by ``persistedStatusRaw``), falling back to
   ``PersistedItemStatus/ready`` for an unknown raw value.
   */
  public var persistedStatus: PersistedItemStatus {
    get { PersistedItemStatus(rawValue: persistedStatusRaw) ?? .ready }
    set { persistedStatusRaw = newValue.rawValue }
  }
}

extension StoredQueueItem {

  /**
   The `Sendable` value projection used to move an item across isolation
   boundaries without touching the `@MainActor` runtime item.
   */
  public var asSnapshot: QueueItemSnapshot {
    QueueItemSnapshot(
      id: id,
      sortIndex: sortIndex,
      sourcePath: sourcePath,
      sourceBookmark: sourceBookmark,
      outputPath: outputPath,
      customName: customName,
      outputFolderBookmark: outputFolderBookmark,
      status: persistedStatus,
      lastError: lastError,
      selection: selection,
      sourceByteCount: sourceByteCount,
      outputByteCount: outputByteCount,
      tracksRemoved: tracksRemoved
    )
  }

  /// Creates a record holding everything `snapshot` carries.
  public convenience init(snapshot: QueueItemSnapshot) {
    self.init()
    apply(snapshot)
  }

  /// Overwrites this record's fields from `snapshot`, in place.
  public func apply(_ snapshot: QueueItemSnapshot) {
    id = snapshot.id
    sortIndex = snapshot.sortIndex
    sourcePath = snapshot.sourcePath
    sourceBookmark = snapshot.sourceBookmark
    outputPath = snapshot.outputPath
    customName = snapshot.customName
    outputFolderBookmark = snapshot.outputFolderBookmark
    persistedStatus = snapshot.status
    lastError = snapshot.lastError
    selection = snapshot.selection
    sourceByteCount = snapshot.sourceByteCount
    outputByteCount = snapshot.outputByteCount
    tracksRemoved = snapshot.tracksRemoved
  }
}

/**
 A `Sendable`, value-type snapshot of a ``StoredQueueItem`` — the seam the
 persistence layer uses to map between SwiftData and the runtime queue.
 */
public struct QueueItemSnapshot: Sendable, Equatable, Identifiable {
  public let id: UUID
  public var sortIndex: Int
  public var sourcePath: String
  public var sourceBookmark: Data?
  public var outputPath: String
  public var customName: String?
  public var outputFolderBookmark: Data?
  public var status: PersistedItemStatus
  public var lastError: String?
  public var selection: FileTrackSelection?
  public var sourceByteCount: Int?
  public var outputByteCount: Int?
  public var tracksRemoved: Int?

  public init(
    id: UUID = UUID(),
    sortIndex: Int = 0,
    sourcePath: String = "",
    sourceBookmark: Data? = nil,
    outputPath: String = "",
    customName: String? = nil,
    outputFolderBookmark: Data? = nil,
    status: PersistedItemStatus = .ready,
    lastError: String? = nil,
    selection: FileTrackSelection? = nil,
    sourceByteCount: Int? = nil,
    outputByteCount: Int? = nil,
    tracksRemoved: Int? = nil
  ) {
    self.id = id
    self.sortIndex = sortIndex
    self.sourcePath = sourcePath
    self.sourceBookmark = sourceBookmark
    self.outputPath = outputPath
    self.customName = customName
    self.outputFolderBookmark = outputFolderBookmark
    self.status = status
    self.lastError = lastError
    self.selection = selection
    self.sourceByteCount = sourceByteCount
    self.outputByteCount = outputByteCount
    self.tracksRemoved = tracksRemoved
  }
}
