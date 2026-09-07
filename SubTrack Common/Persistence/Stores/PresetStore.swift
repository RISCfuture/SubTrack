public import Foundation
public import SwiftData
import os

/**
 Owns preset persistence: stocks a fresh install with the starter presets and
 vends the current presets as value types for the UI to bind to.
 */
@MainActor
@Observable
public final class PresetStore {
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
  #endif

  /// Every preset, by name.
  public private(set) var presets: [Preset] = []

  private let modelContext: ModelContext
  private let sync: (any PresetSyncCoordinating)?
  private let health: PersistenceHealth

  /**
   Creates a store over `modelContext`.

   - Parameter modelContext: The context holding the preset records.
   - Parameter sync: The coordinator reporting when CloudKit has caught up, or
     `nil` when the store is not CloudKit-backed — an in-memory preview, UI
     test, or unit test — in which case the starters are seeded at once.
   - Parameter health: Where this store reports whether it is readable and
     writable. Defaults to a record of its own, which is what a test that
     isn't asking the question wants.
   */
  public init(
    modelContext: ModelContext,
    sync: (any PresetSyncCoordinating)? = nil,
    health: PersistenceHealth = PersistenceHealth()
  ) {
    self.modelContext = modelContext
    self.sync = sync
    self.health = health
    if let sync {
      seedStarters(whenImportSettlesOn: sync)
      sync.onRemoteChange { [weak self] in self?.reload() }
    } else {
      seedStartersIfEmpty()
    }
    reload()
  }

  /**
   Orders two records of the same preset, lowest first.

   Every term is synced content, never local identity: two Macs collapsing the
   same duplicates independently must choose the same survivor, or both delete
   the other's copy and the preset disappears. The string comparisons use `<`
   rather than `localizedStandardCompare` for the same reason — it is
   deterministic and locale-independent, so it belongs in ``reload()``'s
   display sort and nowhere near this one.
   */
  private static func ranksBelow(_ lhs: StoredPreset, _ rhs: StoredPreset) -> Bool {
    (lhs.modifiedAt, lhs.name, lhs.rulesData.base64EncodedString(), lhs.nameTemplate)
      < (rhs.modifiedAt, rhs.name, rhs.rulesData.base64EncodedString(), rhs.nameTemplate)
  }

  /**
   Re-reads presets from the store, first collapsing any records that share an
   `id` — which CloudKit can produce, since it cannot enforce a unique
   constraint. Reading therefore writes, and deliberately so: the duplicates
   have to go before anything reads them as two presets.
   */
  public func reload() {
    // A store that can't be read is not a store with no presets in it. Keeping
    // the presets already in hand shows the user what they had a moment ago,
    // where blanking the list would tell them their presets are gone.
    guard let stored = try? fetchAll() else { return }
    let (survivors, deletedAny) = collapseDuplicates(stored)
    if deletedAny { save() }
    presets = survivors.map(\.asPreset).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  /**
   Inserts a new preset or updates an existing one with the same `id`.

   Does nothing when the store can't be read: without knowing whether this
   preset is already stored, inserting would write a second record for a
   preset the user is editing, not saving the edit they asked for.
   */
  public func save(_ preset: Preset) {
    guard let matches = try? records(for: preset.id) else { return }
    if let existing = matches.first {
      existing.name = preset.name
      existing.rules = preset.rules
      existing.naming = preset.naming
      existing.modifiedAt = .now
    } else {
      modelContext.insert(
        StoredPreset(
          id: preset.id,
          name: preset.name,
          rules: preset.rules,
          naming: preset.naming
        )
      )
    }
    persist()
  }

  /**
   Deletes a preset. Every preset is the user's, so every one can go — every
   record sharing its `id`, in case CloudKit has merged in a duplicate that
   ``reload()`` hasn't collapsed yet, or the deletion would only remove one
   copy and a surviving duplicate would reappear as the preset.
   */
  public func delete(_ preset: Preset) {
    guard let matches = try? records(for: preset.id), !matches.isEmpty else { return }
    for record in matches { modelContext.delete(record) }
    persist()
  }

  /**
   Waits for the first CloudKit import to settle before seeding the starters:
   the store looks empty until then, and seeding early would upload a second
   copy of every starter.

   Only a store that was already empty when the wait began is seeded. Emptiness
   at settle time alone would also cover a store the user emptied while the
   import was in flight, and the starters would reappear over their deletions
   and sync on to their other Macs.

   A store that couldn't be read counts as not empty. The answer is decided
   here and carried into the closure rather than asked again when the import
   settles, which can be ten seconds later: by then the store may read
   perfectly well and look empty for a reason this launch already disproved.
   */
  private func seedStarters(whenImportSettlesOn sync: any PresetSyncCoordinating) {
    let wasEmptyBeforeTheWait = (try? fetchAll())?.isEmpty ?? false
    sync.whenInitialImportSettles { [weak self] in
      guard wasEmptyBeforeTheWait else { return }
      self?.seedStartersIfEmpty()
    }
  }

  /**
   Stocks an empty store with the starter presets — a fresh install. They are
   ordinary presets once written, so nothing re-seeds them while any preset
   remains: editing or deleting one sticks.

   A store that can't be read is not an empty one, and seeding it would write
   the starters on top of presets the user still has — the same mistake as
   mistaking a failed fetch for a fresh install, made against their own data.
   */
  private func seedStartersIfEmpty() {
    guard let stored = try? fetchAll(), stored.isEmpty else { return }
    for starter in Preset.starters {
      modelContext.insert(
        StoredPreset(
          id: starter.id,
          name: starter.name,
          rules: starter.rules,
          naming: starter.naming
        )
      )
    }
    persist()
  }

  /**
   Every stored preset. Throwing rather than falling back to an empty array:
   each caller has its own right answer to an unreadable store, and none of
   them is "the user has no presets".
   */
  private func fetchAll() throws -> [StoredPreset] {
    do {
      #if DEBUG
        // A Cocoa error rather than a `PersistenceError`, so the catch below
        // wraps it exactly once, as it does a real failure from the store.
        if failsFetchesForTesting { throw CocoaError(.fileReadUnknown) }
      #endif
      return try modelContext.fetch(FetchDescriptor<StoredPreset>())
    } catch {
      report(.fetchFailed(detail: String(describing: error)))
      throw error
    }
  }

  private func records(for id: UUID) throws -> [StoredPreset] {
    // The preset set is small; filtering in memory avoids a SwiftData
    // `#Predicate` over UUID, which is unstable across store back ends.
    try fetchAll().filter { $0.id == id }
  }

  /**
   Keeps the highest-ranked record of each `id` and deletes every record that
   ranks strictly below it. A record tied with the survivor on every ranked
   term survives undeleted rather than being picked between: two devices that
   both see a full tie must not each delete the other's copy.
   */
  private func collapseDuplicates(_ allRecords: [StoredPreset]) -> (
    survivors: [StoredPreset], deletedAny: Bool
  ) {
    var deletedAny = false
    let survivors = Dictionary(grouping: allRecords, by: \.id).values.compactMap {
      duplicates -> StoredPreset? in
      guard let survivor = duplicates.max(by: Self.ranksBelow) else { return nil }
      for loser in duplicates where Self.ranksBelow(loser, survivor) {
        modelContext.delete(loser)
        deletedAny = true
      }
      return survivor
    }
    return (survivors, deletedAny)
  }

  private func persist() {
    save()
    reload()
  }

  private func save() {
    do {
      try modelContext.save()
      health.recordSuccess(from: .presets)
    } catch {
      report(.saveFailed(detail: String(describing: error)))
    }
  }

  /// Logs a failure and raises it as the condition the status bar reports.
  private func report(_ failure: PersistenceError) {
    Self.logger.error("\(failure.userMessage, privacy: .public)")
    health.record(failure, from: .presets)
  }
}
