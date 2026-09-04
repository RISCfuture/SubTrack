import Foundation
import SwiftData
import Testing

import SubTrack_Common

@MainActor
@Suite(.serialized)
struct PresetStoreTests {

  private static let container = ModelContainer.inMemory(for: StoredPreset.self)

  private func makeStore() throws -> PresetStore {
    let context = Self.container.mainContext
    try context.delete(model: StoredPreset.self)
    try context.save()
    return PresetStore(modelContext: context)
  }

  @Test
  func `seeds starters into an empty store`() throws {
    let store = try makeStore()
    let seeded: Set<UUID> = Set(store.presets.map(\.id))
    let starters: Set<UUID> = Set(Preset.starters.map(\.id))
    #expect(seeded == starters)
  }

  @Test
  func `saves and reloads custom preset`() throws {
    let store = try makeStore()
    let custom = Preset(
      id: UUID(),
      name: "German",
      rules: SlimRules(languages: ["deu"]),
      naming: OutputNameFormat(template: "{name} [{n}]")
    )
    store.save(custom)

    let reloaded = try #require(store.presets.first { $0.id == custom.id })
    #expect(reloaded.name == "German")
    #expect(reloaded.rules.languages == ["deu"])
    #expect(reloaded.naming == OutputNameFormat(template: "{name} [{n}]"))
  }

  /**
   A record written before formats existed carries no template, and must read
   back as the name those presets already produced.
   */
  @Test
  func `reads a preset with no stored template as the default format`() throws {
    let store = try makeStore()
    let context = Self.container.mainContext
    context.insert(StoredPreset(id: UUID(), name: "Legacy"))
    try context.save()
    store.reload()

    let legacy = try #require(store.presets.first { $0.name == "Legacy" })
    #expect(legacy.naming == .slimmed)
  }

  @Test
  func `updates existing preset in place`() throws {
    let store = try makeStore()
    var custom = Preset(id: UUID(), name: "Draft", rules: .default)
    store.save(custom)
    custom.name = "Final"
    store.save(custom)

    #expect(store.presets.filter { $0.id == custom.id }.count == 1)
    #expect(store.presets.contains { $0.id == custom.id && $0.name == "Final" })
  }

  @Test
  func `deletes any preset including a starter`() throws {
    let store = try makeStore()
    let custom = Preset(id: UUID(), name: "Temp", rules: .default)
    store.save(custom)

    store.delete(custom)
    #expect(!store.presets.contains { $0.id == custom.id })

    // No preset is protected, and a deleted starter stays deleted — nothing
    // re-seeds while any preset remains.
    store.delete(Preset.starters[0])
    #expect(!store.presets.contains { $0.id == Preset.starters[0].id })
    store.reload()
    #expect(!store.presets.contains { $0.id == Preset.starters[0].id })
  }

  /**
   Two Macs can each seed or create the same preset, so several records can
   share an `id`. The survivor is the one ranking highest by modification date,
   then name, then rules — a total order over synced content only.
   */
  @Test
  func `collapses records sharing an ID`() throws {
    let store = try makeStore()
    let context = Self.container.mainContext
    let shared = UUID()
    let old = Date(timeIntervalSince1970: 1_000)
    let recent = Date(timeIntervalSince1970: 2_000)
    context.insert(StoredPreset(id: shared, name: "Stale", modifiedAt: old))
    context.insert(StoredPreset(id: shared, name: "Current", modifiedAt: recent))
    try context.save()

    store.reload()

    let matching = store.presets.filter { $0.id == shared }
    #expect(matching.count == 1)
    #expect(matching.first?.name == "Current")
  }

  /**
   Every device must pick the same survivor, or two Macs delete each other's
   copy and the preset vanishes. The ranking therefore cannot depend on fetch
   or insertion order.
   */
  @Test
  func `picks the same survivor regardless of insertion order`() throws {
    let context = Self.container.mainContext
    let shared = UUID()
    let stamp = Date(timeIntervalSince1970: 3_000)

    func survivorName(insertingBFirst: Bool) throws -> String? {
      let store = try makeStore()
      let names = insertingBFirst ? ["Beta", "Alpha"] : ["Alpha", "Beta"]
      for name in names {
        context.insert(StoredPreset(id: shared, name: name, modifiedAt: stamp))
      }
      try context.save()
      store.reload()
      return store.presets.first { $0.id == shared }?.name
    }

    #expect(try survivorName(insertingBFirst: false) == "Beta")
    #expect(try survivorName(insertingBFirst: true) == "Beta")
  }

  /**
   Two records tied on every ranked term have no way to break the tie
   consistently across devices, so neither is deleted: destroying one would
   let two devices, seeing the same tie, each delete the other's copy and
   lose the preset entirely. The store still presents a single preset for
   the shared `id`.
   */
  @Test
  func `tied duplicates survive without destructive deletion`() throws {
    let store = try makeStore()
    let context = Self.container.mainContext
    let shared = UUID()
    let stamp = Date(timeIntervalSince1970: 4_000)
    context.insert(StoredPreset(id: shared, name: "Twin", modifiedAt: stamp))
    context.insert(StoredPreset(id: shared, name: "Twin", modifiedAt: stamp))
    try context.save()

    store.reload()

    let matching = store.presets.filter { $0.id == shared }
    #expect(matching.count == 1)
    #expect(matching.first?.name == "Twin")

    let stored = try context.fetch(FetchDescriptor<StoredPreset>()).filter { $0.id == shared }
    #expect(stored.count == 2)
  }

  /**
   Against a CloudKit store the starters cannot be seeded until the first
   import settles — the store looks empty until then, so seeding early would
   upload a second copy of every starter.
   */
  @Test
  func `waits for the first import before seeding starters`() throws {
    let context = Self.container.mainContext
    try context.delete(model: StoredPreset.self)
    try context.save()
    let sync = FakePresetSync()

    let store = PresetStore(modelContext: context, sync: sync)
    #expect(store.presets.isEmpty)

    sync.settle()
    #expect(Set(store.presets.map(\.id)) == Set(Preset.starters.map(\.id)))
  }

  /**
   Presets deleted while the first import is still in flight stay deleted: an
   empty store at settle time is also what a user who has just deleted every
   preset leaves behind, and re-seeding there would undo the deletions and
   sync the starters back to their other Macs.
   */
  @Test
  func `does not seed starters into a store emptied during the wait`() throws {
    let context = Self.container.mainContext
    try context.delete(model: StoredPreset.self)
    context.insert(StoredPreset(id: UUID(), name: "Mine"))
    try context.save()
    let sync = FakePresetSync()

    let store = PresetStore(modelContext: context, sync: sync)
    for preset in store.presets { store.delete(preset) }
    #expect(store.presets.isEmpty)

    sync.settle()
    #expect(store.presets.isEmpty)
  }

  /// A preset written on another Mac reaches the UI without any view changing.
  @Test
  func `reloads when another device writes`() throws {
    let context = Self.container.mainContext
    try context.delete(model: StoredPreset.self)
    try context.save()
    let sync = FakePresetSync()
    let store = PresetStore(modelContext: context, sync: sync)
    sync.settle()

    context.insert(StoredPreset(id: UUID(), name: "From Another Mac"))
    try context.save()
    #expect(!store.presets.contains { $0.name == "From Another Mac" })

    sync.sendRemoteChange()
    #expect(store.presets.contains { $0.name == "From Another Mac" })
  }
}

/**
 A ``PresetSyncCoordinating`` the tests drive by hand, standing in for
 ``CloudSyncMonitor`` so no test needs a `CKContainer` or a real store.
 */
@MainActor
final class FakePresetSync: PresetSyncCoordinating {
  private var settleHandlers: [@MainActor () -> Void] = []
  private var remoteChangeHandlers: [@MainActor () -> Void] = []

  func whenInitialImportSettles(_ perform: @escaping @MainActor () -> Void) {
    settleHandlers.append(perform)
  }

  func onRemoteChange(_ perform: @escaping @MainActor () -> Void) {
    remoteChangeHandlers.append(perform)
  }

  /// Fires every pending settle handler, as the first import completing would.
  func settle() {
    let handlers = settleHandlers
    settleHandlers = []
    for handler in handlers { handler() }
  }

  /// Fires every remote-change handler, as another device's write would.
  func sendRemoteChange() {
    for handler in remoteChangeHandlers { handler() }
  }
}
