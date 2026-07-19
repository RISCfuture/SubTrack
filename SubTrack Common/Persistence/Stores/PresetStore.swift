import Foundation
import SwiftData

/**
 Owns preset persistence: stocks a fresh install with the starter presets and
 vends the current presets as value types for the UI to bind to.
 */
@MainActor
@Observable
public final class PresetStore {
  private let modelContext: ModelContext
  private let sync: (any PresetSyncCoordinating)?

  /// Every preset, by name.
  public private(set) var presets: [Preset] = []

  /**
   Creates a store over `modelContext`.

   - Parameter modelContext: The context holding the preset records.
   - Parameter sync: The coordinator reporting when CloudKit has caught up, or
     `nil` when the store is not CloudKit-backed — an in-memory preview, UI
     test, or unit test — in which case the starters are seeded at once.
   */
  public init(modelContext: ModelContext, sync: (any PresetSyncCoordinating)? = nil) {
    self.modelContext = modelContext
    self.sync = sync
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
    let (survivors, deletedAny) = collapseDuplicates(fetchAll())
    if deletedAny { try? modelContext.save() }
    presets = survivors.map(\.asPreset).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  /// Inserts a new preset or updates an existing one with the same `id`.
  public func save(_ preset: Preset) {
    if let existing = record(for: preset.id) {
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
    let matches = records(for: preset.id)
    guard !matches.isEmpty else { return }
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
   */
  private func seedStarters(whenImportSettlesOn sync: any PresetSyncCoordinating) {
    let wasEmptyBeforeTheWait = fetchAll().isEmpty
    sync.whenInitialImportSettles { [weak self] in
      guard wasEmptyBeforeTheWait else { return }
      self?.seedStartersIfEmpty()
    }
  }

  /**
   Stocks an empty store with the starter presets — a fresh install. They are
   ordinary presets once written, so nothing re-seeds them while any preset
   remains: editing or deleting one sticks.
   */
  private func seedStartersIfEmpty() {
    guard fetchAll().isEmpty else { return }
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

  private func fetchAll() -> [StoredPreset] {
    (try? modelContext.fetch(FetchDescriptor<StoredPreset>())) ?? []
  }

  private func records(for id: UUID) -> [StoredPreset] {
    // The preset set is small; filtering in memory avoids a SwiftData
    // `#Predicate` over UUID, which is unstable across store back ends.
    fetchAll().filter { $0.id == id }
  }

  private func record(for id: UUID) -> StoredPreset? {
    records(for: id).first
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
    try? modelContext.save()
    reload()
  }
}
