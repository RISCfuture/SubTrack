import Foundation
import SwiftData
import Testing

import SubTrack_Common

@MainActor
@Suite(.serialized, .sourceFixtures)
struct WorkspacePersistenceTests {

  private static let container = ModelContainer.inMemory(
    for: StoredQueue.self,
    StoredQueueItem.self
  )

  // MARK: - Fixtures

  private func makeContext() throws -> ModelContext {
    let context = Self.container.mainContext
    try context.delete(model: StoredQueue.self)
    try context.delete(model: StoredQueueItem.self)
    try context.save()
    return context
  }

  private func sampleContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
             "disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
  }

  /**
   Simulates a launch: builds a fresh workspace + controller over `context`
   (sharing one governor + stub engine across every queue) and hydrates. Each
   newly created queue is seeded with `seed*` (mirroring the app's default
   preset + app-default destination); a queue restored from the store overrides
   these during hydration.
   */
  private func launch(
    _ context: ModelContext,
    engine: any ConversionEngineProtocol,
    governor: EncodeGovernor,
    seedRules: SlimRules = .default,
    seedPresetID: UUID? = nil,
    seedDestinationBookmark: Data? = nil
  ) -> (Workspace, QueuePersistenceController) {
    let workspace = Workspace { id, name, sortIndex in
      QueueCoordinator(
        id: id,
        name: name,
        sortIndex: sortIndex,
        engine: engine,
        governor: governor,
        settings: QueueSettings(
          rules: seedRules,
          activePresetID: seedPresetID,
          destinationBookmark: seedDestinationBookmark
        ),
        makeBookmark: { Data($0.path(percentEncoded: false).utf8) }
      )
    }
    let controller = QueuePersistenceController(modelContext: context, workspace: workspace)
    controller.load()
    return (workspace, controller)
  }

  private func waitUntil(
    _ timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
  ) async {
    let start = ContinuousClock.now
    while !condition() && ContinuousClock.now - start < timeout {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  // MARK: - Seed

  @Test
  func emptyStoreSeedsExactlyOneQueue() throws {
    let context = try makeContext()
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )

    #expect(workspace.coordinators.count == 1)
    #expect(workspace.coordinators.first?.name == "Queue 1")
    let stored = try context.fetch(FetchDescriptor<StoredQueue>())
    #expect(stored.count == 1)
  }

  // MARK: - Default naming

  @Test
  func defaultQueueNameFillsTheFirstGap() {
    #expect(Workspace.defaultQueueName(existingNames: []) == "Queue 1")
    #expect(Workspace.defaultQueueName(existingNames: ["Queue 1", "Queue 2"]) == "Queue 3")
    // Skips the used numbers and reuses the lowest free one, so a deletion frees it.
    #expect(
      Workspace.defaultQueueName(existingNames: ["Queue 1", "Queue 3", "Movies"]) == "Queue 2"
    )
  }

  // MARK: - Dock progress

  @Test
  func dockProgressSpansEveryQueueWeightedPerItem() async throws {
    let context = try makeContext()
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let movies = workspace.selectedCoordinator
    let shows = workspace.newQueue(name: "Shows")
    await movies.add(try SourceFixtures.make((1...3).map { "dock-movies-\($0).mkv" }))
    await shows.add([try SourceFixtures.make("dock-shows-1.mkv")])
    // Probing counts as work in flight, so settle every item before asserting idle.
    await waitUntil {
      movies.items.count == 3 && shows.items.count == 1
        && (movies.items + shows.items).allSatisfy { $0.status == .ready }
    }

    // Idle: the Dock icon stays plain rather than showing an empty bar.
    #expect(workspace.dockProgress == nil)

    // One of the four items half-encoded → 0.5 / 4. The single-item queue counts
    // for one item, not for half the total.
    movies.items[0].status = .running
    movies.items[0].progress = 0.5
    #expect(workspace.dockProgress == 0.125)

    // The other queue's item finishing lifts the same shared fraction.
    shows.items[0].status = .done
    #expect(workspace.dockProgress == 0.375)

    // Once nothing is in flight the indicator goes away, even mid-queue.
    movies.items[0].status = .cancelled
    #expect(workspace.dockProgress == nil)
  }

  // MARK: - Round-trip across relaunch

  @Test
  func queuesAndItemsRestoreAcrossRelaunch() async throws {
    let context = try makeContext()

    // First launch: rename the seeded queue and populate it.
    let (workspace, controller) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let coordinator = workspace.selectedCoordinator
    workspace.renameQueue(coordinator.id, to: "Movies")

    let urls = try SourceFixtures.make(["A", "B", "C", "D"].map { "rt-\($0).mkv" })
    await coordinator.add(urls)
    await waitUntil {
      coordinator.items.count == 4 && coordinator.items.allSatisfy { $0.status == .ready }
    }

    // A non-default run order, applied while every item is still reorderable.
    let ids = coordinator.items.map(\.id)
    coordinator.moveItems([ids[3]], before: ids[0])  // → D, A, B, C
    #expect(coordinator.items.map(\.id) == [ids[3], ids[0], ids[1], ids[2]])

    // Settle a spread of states: a selection, a done, a failed(reason), and an
    // in-flight item that must collapse to ready on restore.
    let byID = Dictionary(uniqueKeysWithValues: coordinator.items.map { ($0.id, $0) })
    let selection = FileTrackSelection(choices: [
      TrackChoice(
        streamIndex: 1,
        streamType: .audio,
        action: .convert(codec: "aac", options: ["-b:a", "192k"])
      )
    ])
    byID[ids[0]]?.selection = selection  // A: ready + selection
    byID[ids[1]]?.status = .done  // B: done, with slimming results
    byID[ids[1]]?.sourceByteCount = 1_200_000_000
    byID[ids[1]]?.outputByteCount = 780_000_000
    byID[ids[1]]?.tracksRemoved = 2
    byID[ids[2]]?.status = .failed("boom")  // C: failed(reason)
    byID[ids[3]]?.status = .running  // D: running → ready
    controller.persistAll()

    // Second launch on the same store.
    let (restored, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    #expect(restored.coordinators.count == 1)
    let reloaded = try #require(restored.coordinators.first)
    #expect(reloaded.name == "Movies")

    // Re-probe of ready items runs on load; wait for it to settle.
    await waitUntil {
      reloaded.items.count == 4 && !reloaded.items.contains { $0.status == .probing }
    }
    let items = reloaded.items
    #expect(
      items.map(\.sourceURL.lastPathComponent) == [
        "rt-D.mkv", "rt-A.mkv", "rt-B.mkv", "rt-C.mkv"
      ]
    )

    #expect(items[0].status == .ready)  // D was running → ready
    #expect(items[1].status == .ready)  // A stays ready
    #expect(items[1].selection == selection)  // selection round-trips

    // Both bookmarks survive the relaunch: the source's, and the one for the
    // folder its output lands in. Neither can be re-minted once the transient
    // grant is gone, and losing the folder one leaves a restored item able to
    // read its input but not create the output beside it.
    let sourceA = urls[0]
    #expect(items[1].sourceBookmark == Data(sourceA.path(percentEncoded: false).utf8))
    #expect(
      items[1].outputFolderBookmark
        == Data(sourceA.deletingLastPathComponent().path(percentEncoded: false).utf8)
    )
    #expect(items[2].status == .done)  // B
    #expect(items[2].sourceByteCount == 1_200_000_000)  // slimming numbers survive
    #expect(items[2].outputByteCount == 780_000_000)
    #expect(items[2].tracksRemoved == 2)
    #expect(isFailed(items[3].status, reason: "boom"))  // C
  }

  // MARK: - Per-queue settings

  @Test
  func perQueueRulesAndDestinationsRestoreDistinctly() throws {
    let context = try makeContext()
    let (workspace, controller) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let first = workspace.selectedCoordinator
    let second = workspace.newQueue(name: "Second")

    let firstRules = SlimRules(languages: ["eng"], includeOtherAudio: false),
      secondRules = SlimRules(languages: ["jpn", "eng"], includeOtherAudio: true)
    let firstPreset = UUID(), secondPreset = UUID()
    first.settings.rules.rules = firstRules
    first.settings.rules.activePresetID = firstPreset
    first.settings.destination.load(Data("dest-first".utf8))
    second.settings.rules.rules = secondRules
    second.settings.rules.activePresetID = secondPreset
    second.settings.destination.load(Data("dest-second".utf8))
    controller.persistAll()

    let firstID = first.id, secondID = second.id

    // Relaunch on the same store: each queue restores its own settings.
    let (restored, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let restoredFirst = try #require(restored.coordinators.first { $0.id == firstID })
    let restoredSecond = try #require(restored.coordinators.first { $0.id == secondID })

    #expect(restoredFirst.settings.rules.rules == firstRules)
    #expect(restoredFirst.settings.rules.activePresetID == firstPreset)
    #expect(restoredFirst.settings.destination.bookmarkData == Data("dest-first".utf8))
    #expect(restoredSecond.settings.rules.rules == secondRules)
    #expect(restoredSecond.settings.rules.activePresetID == secondPreset)
    #expect(restoredSecond.settings.destination.bookmarkData == Data("dest-second".utf8))
  }

  @Test
  func applyingPresetToOneQueueLeavesAnotherUnchanged() throws {
    let context = try makeContext()
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let first = workspace.selectedCoordinator
    let second = workspace.newQueue(name: "Second")

    let baseline = SlimRules(languages: ["eng"])
    first.settings.rules.rules = baseline
    second.settings.rules.rules = baseline

    let preset = Preset(
      id: UUID(),
      name: "Loud",
      rules: SlimRules(languages: ["jpn"], includeOtherAudio: true)
    )
    first.settings.apply(preset)

    #expect(first.settings.rules.rules == preset.rules)
    #expect(first.settings.rules.activePresetID == preset.id)
    #expect(second.settings.rules.rules == baseline)
    #expect(second.settings.rules.activePresetID == nil)
  }

  @Test
  func newQueueSeedsDefaultPresetAndDestination() throws {
    let context = try makeContext()
    let presetID = UUID()
    let defaultRules = SlimRules(languages: ["eng", "fra"])
    let defaultBookmark = Data("app-default-dest".utf8)
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor(),
      seedRules: defaultRules,
      seedPresetID: presetID,
      seedDestinationBookmark: defaultBookmark
    )

    // The seeded "Queue 1" starts from the default preset + app-default destination…
    let seeded = try #require(workspace.coordinators.first)
    #expect(seeded.settings.rules.rules == defaultRules)
    #expect(seeded.settings.rules.activePresetID == presetID)
    #expect(seeded.settings.destination.bookmarkData == defaultBookmark)

    // …and so does a queue added later.
    let added = workspace.newQueue(name: "Added")
    #expect(added.settings.rules.rules == defaultRules)
    #expect(added.settings.rules.activePresetID == presetID)
    #expect(added.settings.destination.bookmarkData == defaultBookmark)
  }

  // MARK: - Governor

  @Test
  func governorCapsConcurrencyAcrossQueues() async throws {
    let context = try makeContext()
    let governor = EncodeGovernor(limit: 1)
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer(), holdUntilCancelled: true),
      governor: governor
    )
    // Two queues, each with one startable item, sharing the one governor.
    let first = workspace.selectedCoordinator
    let second = workspace.newQueue(name: "Second")
    await first.add([try SourceFixtures.make("gov-1.mkv")])
    await second.add([try SourceFixtures.make("gov-2.mkv")])
    await waitUntil { first.items.first?.status == .ready && second.items.first?.status == .ready }

    first.startAll()
    second.startAll()
    await waitUntil { governor.activeCount == 1 }

    // The global limit of 1 is respected: one item runs, the other waits.
    #expect(governor.activeCount == 1)
    #expect(first.activeCount + second.activeCount == 1)

    // Freeing the slot hands it to the waiting queue.
    let running = first.activeCount == 1 ? first : second
    let waiting = first.activeCount == 1 ? second : first
    running.cancelAll()
    await waitUntil { waiting.activeCount == 1 }
    #expect(waiting.activeCount == 1)
    #expect(governor.activeCount == 1)
  }

  @Test
  func governorHoldsOffIdleSleepWhileEncoding() async throws {
    let context = try makeContext()
    let governor = EncodeGovernor()
    let (workspace, _) = launch(
      context,
      engine: StubEngine(container: try sampleContainer(), holdUntilCancelled: true),
      governor: governor
    )
    let coordinator = workspace.selectedCoordinator
    await coordinator.add([try SourceFixtures.make("sleep-1.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    // An idle queue holds nothing; a slot in flight holds the activity…
    #expect(!governor.isHoldingActivity)
    coordinator.startAll()
    await waitUntil { governor.activeCount == 1 }
    #expect(governor.isHoldingActivity)

    // …and the last slot to free hands it back, so nothing outlives the run.
    coordinator.cancelAll()
    await waitUntil { governor.activeCount == 0 }
    #expect(!governor.isHoldingActivity)
  }

  // MARK: - Write-through discipline

  @Test
  func progressDoesNotPersistButSettledStatusDoes() async throws {
    let counter = ChangeCounter()
    let coordinator = QueueCoordinator(
      engine: StubEngine(container: try sampleContainer()),
      onPersistableChange: { counter.bump() }
    )
    await coordinator.add([try SourceFixtures.make("wt.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    // A full run streams `.running` then `progress` events before finishing;
    // only the settled `.done` may write through.
    counter.reset()
    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done }
    #expect(counter.count == 1)
  }

  @Test
  func settledChangesReachTheStoreWithoutAnExplicitSave() async throws {
    let context = try makeContext()
    let (workspace, controller) = launch(
      context,
      engine: StubEngine(container: try sampleContainer()),
      governor: EncodeGovernor()
    )
    let coordinator = workspace.selectedCoordinator

    // Adding a folder settles one item at a time, and those writes are collected
    // rather than performed one per settling — but every one of them still has to
    // land, with nothing but the passage of time to make it happen.
    await coordinator.add(try SourceFixtures.make((1...12).map { "coalesced-\($0).mkv" }))
    await waitUntil { coordinator.items.allSatisfy { $0.status == .ready } }
    await waitUntil {
      ((try? context.fetch(FetchDescriptor<StoredQueue>()))?.first?.items?.count ?? 0) == 12
    }

    let stored = try #require(try context.fetch(FetchDescriptor<StoredQueue>()).first)
    #expect(stored.items?.count == 12)

    // The write-through hook holds the controller weakly, so the app's own
    // session-long reference is what keeps it working — model that here rather
    // than let the controller go and test a queue that writes nothing.
    withExtendedLifetime(controller) {}
  }

  // MARK: - Helpers

  private func isFailed(_ status: QueueItemState, reason: String) -> Bool {
    if case .failed(let message) = status { return message == reason }
    return false
  }
}

/// Counts ``QueueCoordinator/onPersistableChange`` firings on the main actor.
@MainActor
private final class ChangeCounter {
  private(set) var count = 0

  func bump() { count += 1 }
  func reset() { count = 0 }
}
