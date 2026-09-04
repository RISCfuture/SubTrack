import Foundation
import Testing

import SubTrack_Common

@MainActor
@Suite
struct QueueCoordinatorTests {

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
   A five-managed-stream container (1 video, 2 audio, 2 subtitle) for
   exercising tracks-removed math.
   */
  private func fiveStreamContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
             "disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":2,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
             "bits_per_sample":0,"disposition":{},"tags":{"language":"fra"}},
            {"index":3,"codec_name":"subrip","codec_type":"subtitle",
             "disposition":{"default":1},"tags":{"language":"eng"}},
            {"index":4,"codec_name":"subrip","codec_type":"subtitle",
             "disposition":{},"tags":{"language":"fra"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"5000"}
        }
        """.utf8
      )
    )
  }

  /**
   ``fiveStreamContainer()``'s tracks with `BPS` tags, so the bytes a dropped
   track reclaims can be derived. Over the 60-second duration the tracks weigh
   60 MB, 960 kB, 4.8 MB, 7.5 kB, and 15 kB respectively.
   */
  private func bitRatedContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
             "disposition":{"default":1},"tags":{"language":"eng","BPS":"8000000"}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             \
        "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"eng","BPS":"128000"}},
            {"index":2,"codec_name":"ac3","codec_type":"audio","sample_rate":"48000","channels":6,
             "bits_per_sample":0,"disposition":{},"tags":{"language":"fra","BPS":"640000"}},
            {"index":3,"codec_name":"subrip","codec_type":"subtitle",
             "disposition":{"default":1},"tags":{"language":"eng","BPS":"1000"}},
            {"index":4,"codec_name":"subrip","codec_type":"subtitle",
             "disposition":{},"tags":{"language":"fra","BPS":"2000"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"66000000"}
        }
        """.utf8
      )
    )
  }

  /// A container whose only audio is Chinese, so English-only rules drop all of it.
  private func chineseAudioContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1440,"height":1080,
             "disposition":{"default":1},"tags":{}},
            {"index":1,"codec_name":"aac","codec_type":"audio","sample_rate":"48000","channels":2,
             "bits_per_sample":0,"disposition":{"default":1},"tags":{"language":"chi"}},
            {"index":2,"codec_name":"subrip","codec_type":"subtitle",
             "disposition":{"default":1},"tags":{"language":"eng"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
  }

  /// A container with no audio at all.
  private func silentContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1440,"height":1080,
             "disposition":{"default":1},"tags":{}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
  }

  /**
   Keeps the video, the English audio, and the English subtitles; drops the
   French audio and subtitles.
   */
  private func dropFrenchTracks() -> FileTrackSelection {
    FileTrackSelection(choices: [
      TrackChoice(streamIndex: 0, streamType: .video, action: .copy),
      TrackChoice(streamIndex: 1, streamType: .audio, action: .copy),
      TrackChoice(streamIndex: 2, streamType: .audio, action: .drop),
      TrackChoice(streamIndex: 3, streamType: .subtitle, action: .copy),
      TrackChoice(streamIndex: 4, streamType: .subtitle, action: .drop)
    ])
  }

  /**
   The volume is reported as unmeasurable by default, so every test that isn't
   about the space preflight takes the same fail-open path an SMB destination
   would.
   */
  private func makeCoordinator(
    _ engine: any ConversionEngineProtocol,
    probeCapabilities: @escaping @Sendable () async -> EncoderCapabilities? = { nil },
    availableCapacity: @escaping @MainActor (URL) -> Int? = { _ in nil }
  ) -> QueueCoordinator {
    QueueCoordinator(
      engine: engine,
      probeCapabilities: probeCapabilities,
      availableCapacity: availableCapacity
    )
  }

  /**
   A coordinator wired to a fresh undo manager, and that manager.

   Event grouping is off because it closes a group when the main run loop next
   spins, which a unit test can neither promise nor await; every edit here is
   grouped explicitly by ``undoably(_:_:)`` instead.
   */
  private func makeUndoableCoordinator(
    _ engine: any ConversionEngineProtocol
  ) -> (QueueCoordinator, UndoManager) {
    let coordinator = makeCoordinator(engine)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    coordinator.undoManager = undoManager
    return (coordinator, undoManager)
  }

  /**
   Runs one edit as its own undo group, standing in for the window's grouping.

   For edits that register something. An empty group is still pushed, so an
   edit expected to register nothing is called bare — which is also the sharper
   assertion, since the stack then has to stay empty.
   */
  private func undoably(_ undoManager: UndoManager, _ edit: () -> Void) {
    undoManager.beginUndoGrouping()
    edit()
    undoManager.endUndoGrouping()
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

  /// Waits for the coordinator to finish probing everything it has queued.
  private func waitUntilSettled(_ coordinator: QueueCoordinator) async throws {
    for _ in 0..<200 where coordinator.isRunning {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!coordinator.isRunning)
  }

  /**
   A real, empty `.mkv` file for tests that route through
   ``QueueCoordinator/ingest(_:)``, which — unlike ``QueueCoordinator/add(_:)``
   — resolves paths through `MovieFileFinder` and so requires the source to
   actually exist on disk.
   */
  private func makeTemporaryMovieFile() throws -> URL {
    let file = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-\(UUID().uuidString).mkv", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: file)
    return file
  }

  /// Real temporary `.mkv` files, since `ingest` filters to paths that exist.
  private func makeTemporaryMovieFiles(_ count: Int) throws -> [URL] {
    try (0..<count).map { _ in try makeTemporaryMovieFile() }
  }

  @Test
  func `ingest adds each source once`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    let url = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: url) }
    await coordinator.ingestAsync([url, url])
    await coordinator.ingestAsync([url])

    #expect(coordinator.items.count == 1)
  }

  /**
   The sheet's state must exist while an ingest runs and be gone afterward.

   The mid-ingest half is read from inside the ingest rather than from a
   bystander: minting an item's bookmark happens partway through
   ``QueueCoordinator/add(_:reporting:)``, on the main actor, at a point the
   sheet is by definition still up.
   */
  @Test
  func `ingest clears its progress when done`() async throws {
    let url = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: url) }

    let observer = IngestProgressObserver()
    let coordinator = QueueCoordinator(
      engine: StubEngine(container: try sampleContainer()),
      makeBookmark: { _ in
        observer.recordSheetState()
        return nil
      }
    )
    observer.coordinator = coordinator
    #expect(coordinator.ingestProgress == nil)

    await coordinator.ingestAsync([url])

    #expect(observer.sawSheetState)
    #expect(coordinator.ingestProgress == nil)
  }

  /**
   Probes are bounded, so a large add never holds more security scopes than
   the probe coordinator will run reads for.
   */
  @Test
  func `ingest bounds concurrent probes`() async throws {
    let engine = StubEngine(container: try sampleContainer())
    engine.probeDelay = .milliseconds(50)
    let coordinator = makeCoordinator(engine)

    let urls = try makeTemporaryMovieFiles(20)
    defer { for url in urls { try? FileManager.default.removeItem(at: url) } }
    await coordinator.ingestAsync(urls)

    // Guards against the whole test passing vacuously on an empty queue.
    #expect(coordinator.items.count == 20)
    let probing = coordinator.items.count { $0.status == .probing }
    #expect(probing <= ProbeCoordinator.defaultLimit)
  }

  @Test
  func `add probes a file to ready`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add([try SourceFixtures.make("a.mkv")])

    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)
    #expect(item.status == .ready)
    #expect(item.container != nil)
    #expect(item.trackSummary == "1V 1A")
  }

  @Test
  func `runs item to completion`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add([try SourceFixtures.make("b.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    // Wait for the run task to fully tear down (clear itself from `runTasks`),
    // not just for `.done` to appear — the task sets `.done` and only then, after
    // another suspension, deregisters, so asserting `isRunning` right at `.done`
    // races that teardown.
    await waitUntil { coordinator.items.first?.status == .done && !coordinator.isRunning }

    let item = try #require(coordinator.items.first)
    #expect(item.status == .done)
    #expect(item.progress == 1)
    #expect(coordinator.isRunning == false)
  }

  @Test
  func `changing the name format renames only pending items`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add(try SourceFixtures.make(["format-a.mkv", "format-b.mkv"]))
    await waitUntil { coordinator.items.allSatisfy { $0.status == .ready } }

    coordinator.start([coordinator.items[0].id])
    await waitUntil { coordinator.items[0].status == .done && !coordinator.isRunning }
    let finishedOutput = coordinator.items[0].outputURL

    coordinator.settings.editNaming(OutputNameFormat(template: "{name} [{n}]"))

    #expect(coordinator.items[0].outputURL == finishedOutput)
    #expect(coordinator.items[1].outputURL.lastPathComponent == "format-b [2].mkv")
  }

  @Test
  func `naming one file leaves the others numbering alone`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    coordinator.settings.editNaming(OutputNameFormat(template: "{name} [{n}]"))
    await coordinator.add(try SourceFixtures.make(["named-a.mkv", "named-b.mkv", "named-c.mkv"]))
    await waitUntil { coordinator.items.allSatisfy { $0.status == .ready } }

    coordinator.setCustomName("Middle", for: coordinator.items[1])

    #expect(coordinator.items[1].outputURL.lastPathComponent == "Middle.mkv")
    // The named file keeps its turn, so the third file is still the third.
    #expect(coordinator.items[2].outputURL.lastPathComponent == "named-c [3].mkv")
  }

  @Test
  func `two files given the same name conflict`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    coordinator.settings.destination.setDestination(URL(filePath: "/tmp/nonexistent-out"))
    await coordinator.add(try SourceFixtures.make(["clash-a.mkv", "clash-b.mkv"]))
    await waitUntil { coordinator.items.allSatisfy { $0.status == .ready } }

    for item in coordinator.items { coordinator.setCustomName("Same", for: item) }

    #expect(
      coordinator.outputNameConflicts == [
        .duplicateOutputs(
          name: "Same.mkv",
          sources: coordinator.items.map(\.sourceURL)
        )
      ]
    )
  }

  @Test
  func `a name conflict keeps the queue from starting`() async throws {
    let source = try SourceFixtures.make("clash.mkv")
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add([source])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.settings.editNaming(OutputNameFormat(template: "{name}"))
    #expect(coordinator.outputNameConflicts == [.overwritesSource(sources: [source])])

    coordinator.startAll()
    #expect(coordinator.items.first?.status == .ready)
    #expect(coordinator.isRunning == false)
  }

  @Test
  func `cancel stops running item`() async throws {
    let coordinator = makeCoordinator(
      StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    )
    await coordinator.add([try SourceFixtures.make("c.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil {
      coordinator.items.first?.status == .running && coordinator.items.first?.progress == 0.5
    }
    #expect(coordinator.items.first?.status == .running)

    coordinator.cancelAll()
    await waitUntil { coordinator.items.first?.status == .cancelled }
    #expect(coordinator.items.first?.status == .cancelled)
  }

  @Test
  func `reorder moves startable items but not finished`() async throws {
    let (coordinator, undoManager) = makeUndoableCoordinator(
      StubEngine(container: try sampleContainer())
    )
    let urls = try SourceFixtures.make((0..<3).map { "reorder-\($0).mkv" })
    await coordinator.add(urls)
    await waitUntil {
      coordinator.items.count == 3 && coordinator.items.allSatisfy { $0.status == .ready }
    }

    let ids = coordinator.items.map(\.id)

    // Finishing the first item makes it non-reorderable.
    coordinator.start([ids[0]])
    await waitUntil { coordinator.items.first(where: { $0.id == ids[0] })?.status == .done }

    // A finished item is ignored, leaving the order untouched.
    coordinator.moveItems([ids[0]], to: 2)
    #expect(coordinator.items.map(\.id) == ids)

    // Dropping a row either side of where it already sits is a no-op.
    coordinator.moveItems([ids[2]], to: 2)
    #expect(coordinator.items.map(\.id) == ids)
    coordinator.moveItems([ids[2]], to: 3)
    #expect(coordinator.items.map(\.id) == ids)

    // None of those drops left anything to take back — a reorder that didn't
    // happen must not consume the user's ⌘Z.
    #expect(!undoManager.canUndo)

    // Ready items reorder, and the finished item keeps its slot.
    undoably(undoManager) { coordinator.moveItems([ids[2]], to: 1) }
    #expect(coordinator.items.map(\.id) == [ids[0], ids[2], ids[1]])
    #expect(undoManager.undoActionName == "Reorder Queue")

    // Restored from a whole-order snapshot: `moveItems` is not its own inverse.
    undoManager.undo()
    #expect(coordinator.items.map(\.id) == ids)

    undoManager.redo()
    #expect(coordinator.items.map(\.id) == [ids[0], ids[2], ids[1]])
  }

  /**
   The whole of an undone removal: the rows come back where they were rather
   than appended, as the very same objects — which is what carries the
   bookmarks and the hand-set overrides a re-add could never recover — with the
   selection they were part of and the numbering their absence had shifted.
   */
  @Test
  func `undo puts removed items back where they were`() async throws {
    let (coordinator, undoManager) = makeUndoableCoordinator(
      StubEngine(container: try sampleContainer())
    )
    coordinator.settings.editNaming(OutputNameFormat(template: "{name} {n}"))
    await coordinator.add(try SourceFixtures.make((0..<3).map { "undo-\($0).mkv" }))
    await waitUntil {
      coordinator.items.count == 3 && coordinator.items.allSatisfy { $0.status == .ready }
    }

    let ids = coordinator.items.map(\.id)
    let middle = coordinator.items[1]
    coordinator.setCustomName("hand-named", for: middle)
    coordinator.selection = [ids[0], ids[1]]

    undoably(undoManager) { coordinator.remove([ids[1]]) }
    #expect(coordinator.items.map(\.id) == [ids[0], ids[2]])
    #expect(coordinator.selection == [ids[0]])
    #expect(coordinator.items[1].outputURL.lastPathComponent == "undo-2 2.mkv")
    #expect(undoManager.undoActionName == "Remove from Queue")

    undoManager.undo()
    #expect(coordinator.items.map(\.id) == ids)
    #expect(coordinator.items[1] === middle)
    #expect(coordinator.items[1].customName == "hand-named")
    #expect(coordinator.selection == [ids[0], ids[1]])
    #expect(coordinator.items[2].outputURL.lastPathComponent == "undo-2 3.mkv")

    undoManager.redo()
    #expect(coordinator.items.map(\.id) == [ids[0], ids[2]])
    #expect(coordinator.selection == [ids[0]])

    // A torn-down queue takes its actions with it: the stack holds the
    // coordinator unowned, so one left behind is a crash waiting for a ⌘Z.
    coordinator.teardown()
    #expect(!undoManager.canUndo)
    #expect(!undoManager.canRedo)
  }

  /// An item removed mid-run comes back settled and restartable, never running.
  @Test
  func `undo brings back a removed running item as settled`() async throws {
    let (coordinator, undoManager) = makeUndoableCoordinator(
      StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    )
    await coordinator.add([try SourceFixtures.make("interrupted.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .running }
    let id = try #require(coordinator.items.first?.id)

    undoably(undoManager) { coordinator.remove([id]) }
    undoManager.undo()

    await waitUntil { coordinator.items.first?.status == .cancelled }
    #expect(coordinator.items.first?.status == .cancelled)
    #expect(coordinator.items.first?.status.isStartable == true)
    #expect(!coordinator.hasEncodeWorkInFlight)
  }

  /**
   Clear Completed is one named undo over the finished items alone, and none at
   all when nothing has finished — an edit that did nothing must not swallow the
   user's ⌘Z, nor rename the edit sitting under it.
   */
  @Test
  func `clear completed is one named undo, and nothing when empty`() async throws {
    let (coordinator, undoManager) = makeUndoableCoordinator(
      StubEngine(container: try sampleContainer())
    )
    await coordinator.add(try SourceFixtures.make(["cleared.mkv", "kept.mkv"]))
    await waitUntil {
      coordinator.items.count == 2 && coordinator.items.allSatisfy { $0.status == .ready }
    }

    coordinator.clearCompleted()
    #expect(!undoManager.canUndo)

    let ids = coordinator.items.map(\.id)
    coordinator.start([ids[0]])
    await waitUntil { coordinator.items.first?.status == .done }

    undoably(undoManager) { coordinator.clearCompleted() }
    #expect(coordinator.items.map(\.id) == [ids[1]])
    #expect(undoManager.undoActionName == "Clear Completed")

    undoManager.undo()
    #expect(coordinator.items.map(\.id) == ids)
    // Back as `done`, not merely present: the savings and slimmed-file rollups
    // both count finished items, and would quietly lose this one otherwise.
    #expect(coordinator.items.first?.status == .done)
    #expect(coordinator.slimmedCount == 1)
  }

  /**
   A restored item is watched again. Nothing else in the app observes whether a
   source monitor was installed, so a removal that drops one and an undo that
   fails to re-arm it are invisible until a file vanishes unnoticed.
   */
  @Test
  func `a restored item is watched again`() async throws {
    let (coordinator, undoManager) = makeUndoableCoordinator(
      StubEngine(container: try sampleContainer())
    )
    let source = try SourceFixtures.make("watched.mkv")
    await coordinator.add([source])
    await waitUntil { coordinator.items.first?.status == .ready }

    let id = try #require(coordinator.items.first?.id)
    undoably(undoManager) { coordinator.remove([id]) }
    undoManager.undo()
    #expect(coordinator.items.count == 1)

    try FileManager.default.removeItem(at: source)
    await waitUntil { coordinator.items.first?.status == .missing }
    #expect(coordinator.items.first?.status == .missing)
  }

  /**
   Both child-process paths — the probe and the run — must read the source
   through the bookmark's resolved URL under an open security-scoped grant.
   A probe that skips the grant reaches a sandboxed source only while the
   transient grant from its drop survives, so it works when the file is added
   and fails on every re-scan after relaunch.
   */
  @Test
  func `probe and run read source from resolved bookmark`() async throws {
    let recorder = JobInputRecorder()
    let resolved = URL(filePath: "/tmp/subtrack-resolved-source.mkv")
    let coordinator = QueueCoordinator(
      engine: RecordingEngine(container: try sampleContainer(), recorder: recorder),
      makeBookmark: { _ in Data("bookmark".utf8) },
      beginSourceAccess: { _ in ScopedAccess(resolvedURL: resolved) {} }
    )
    await coordinator.add([try SourceFixtures.make("original-source.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    // The bookmark is captured at add time...
    let item = try #require(coordinator.items.first)
    #expect(item.sourceBookmark == Data("bookmark".utf8))

    // ...the probe reads from the grant's resolved location...
    let probedInput = await recorder.probed
    #expect(probedInput == resolved)

    // ...and so does the run.
    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done }
    let recordedInput = await recorder.input
    #expect(recordedInput == resolved)
  }

  /**
   Writing beside the source needs a grant to the *folder*, not the file: a
   source bookmark scopes the source itself, and a file-scoped sandbox grant
   can't create a sibling next to it. The folder bookmark has to be captured
   at add time because the transient grant it's minted from is gone by the
   next launch — an item restored without one can read its input and write
   nothing.
   */
  @Test
  func `add bookmarks the folder output lands in beside the source`() async throws {
    let coordinator = QueueCoordinator(
      engine: StubEngine(container: try sampleContainer()),
      makeBookmark: { Data($0.path(percentEncoded: false).utf8) }
    )
    let source = URL(filePath: "/tmp/subtrack-folder-bookmark/clip.mkv")
    await coordinator.add([source])
    await waitUntil { coordinator.items.first?.status == .ready }

    let item = try #require(coordinator.items.first)
    let folder = source.deletingLastPathComponent()
    #expect(item.sourceBookmark == Data(source.path(percentEncoded: false).utf8))
    #expect(item.outputFolderBookmark == Data(folder.path(percentEncoded: false).utf8))
  }

  /**
   Output inside the queue's destination is already covered by that folder's
   own bookmark, so the item doesn't carry a second one for it.
   */
  @Test
  func `add skips the folder bookmark when the destination covers output`() async throws {
    let coordinator = QueueCoordinator(
      engine: StubEngine(container: try sampleContainer()),
      makeBookmark: { Data($0.path(percentEncoded: false).utf8) }
    )
    coordinator.settings.destination.setDestination(
      URL(filePath: "/tmp/subtrack-destination", directoryHint: .isDirectory)
    )
    await coordinator.add([URL(filePath: "/tmp/subtrack-elsewhere/clip.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    let item = try #require(coordinator.items.first)
    #expect(item.outputFolderBookmark == nil)
  }

  /**
   A sandbox denial on the output reaches the user only as `ffmpeg`'s opaque
   "Operation not permitted", so an unwritable output folder settles the item
   with an actionable error instead of being handed to the engine.
   */
  @Test
  func `run fails up front when the output folder is not writable`() async throws {
    let folder = URL(
      filePath: "/tmp/subtrack-absent-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add([folder.appending(path: "clip.mkv", directoryHint: .notDirectory)])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status.needsAttention == true }

    let item = try #require(coordinator.items.first)
    #expect(
      item.status == .failed(FileAccessError.outputFolderNotWritable(url: folder).userMessage)
    )
    #expect(item.progress == 0)
  }

  /**
   A queued item whose plan drops the French tracks. Given
   ``bitRatedContainer()`` its projected output is the 61,185,000 bytes
   ``outputSizeMovesFromPlanToProjectionToMeasurement`` pins, which is the
   number the space preflight compares against.
   */
  private func makeSlimmableItem(
    _ coordinator: QueueCoordinator,
    source: URL
  ) async throws -> QueueItem {
    await coordinator.add([source])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)
    item.sourceByteCount = 66_000_000
    item.selection = dropFrenchTracks()
    return item
  }

  /**
   Filling a disk otherwise reaches the user as `ffmpeg exited with code N`, so
   a projection the volume plainly can't hold settles the item up front with an
   error that says what happened.
   */
  @Test
  func `run fails up front when the output volume has no room`() async throws {
    let source = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: source) }
    let coordinator = makeCoordinator(
      StubEngine(container: try bitRatedContainer()),
      availableCapacity: { _ in 1_000_000 }
    )
    let item = try await makeSlimmableItem(coordinator, source: source)

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status.needsAttention == true }

    #expect(
      item.status
        == .failed(
          VideoProcessingError.insufficientSpace(required: 61_185_000, available: 1_000_000)
            .userMessage
        )
    )
    #expect(item.progress == 0)
  }

  /**
   `volumeAvailableCapacityForImportantUsage` is unavailable on SMB and NFS,
   which is an ordinary destination for this app. An unanswerable volume has to
   let the run through — refusing work that would have succeeded is worse than
   the error message the check exists to improve.
   */
  @Test
  func `run proceeds when the volume won't report its free space`() async throws {
    let source = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: source) }
    let coordinator = makeCoordinator(
      StubEngine(container: try bitRatedContainer()),
      availableCapacity: { _ in nil }
    )
    let item = try await makeSlimmableItem(coordinator, source: source)

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done }

    #expect(item.status == .done)
  }

  /**
   The other half of failing open: a plan whose output size can't be projected
   — a transcode, or dropped tracks that declare no bit rate — runs even on a
   volume reporting nothing free.
   */
  @Test
  func `run proceeds when the output size cannot be projected`() async throws {
    let source = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: source) }
    let coordinator = makeCoordinator(
      StubEngine(container: try fiveStreamContainer()),
      availableCapacity: { _ in 0 }
    )
    let item = try await makeSlimmableItem(coordinator, source: source)
    #expect(coordinator.outputSize(for: item) == nil)

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done }

    #expect(item.status == .done)
  }

  @Test
  func `revalidate marks missing then recovers`() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "clip.mkv", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: file)

    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    await coordinator.add([file])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)

    try FileManager.default.removeItem(at: file)
    coordinator.revalidate(item)
    #expect(item.status == .missing)

    try Data("x".utf8).write(to: file)
    coordinator.revalidate(item)
    #expect(item.status == .ready)

    try? FileManager.default.removeItem(at: directory)
  }

  /**
   A re-scan refreshes the cached container, and a finished item settles back
   to `done` rather than `ready` — otherwise it would drop out of the queue's
   slimmed-count and saved-bytes rollups, which both filter on `.done`.
   */
  @Test
  func `rescan refreshes container and keeps finished items done`() async throws {
    let engine = StubEngine(container: try sampleContainer())
    let coordinator = makeCoordinator(engine)
    await coordinator.add([try SourceFixtures.make("rescan.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done && !coordinator.isRunning }
    let item = try #require(coordinator.items.first)
    #expect(item.trackSummary == "1V 1A")

    // The same source now probes as a richer container.
    engine.container = try fiveStreamContainer()
    coordinator.rescan([item.id])
    await waitUntil { item.status != .probing && item.trackSummary == "1V 2A 2S" }

    #expect(item.trackSummary == "1V 2A 2S")
    #expect(item.status == .done)
  }

  /**
   An encoding item is skipped: re-probing underneath a live `ffmpeg` run
   would replace the container its operations were derived from.
   */
  @Test
  func `rescan skips running items`() async throws {
    let coordinator = makeCoordinator(
      StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    )
    await coordinator.add([try SourceFixtures.make("rescan-busy.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .running }
    let item = try #require(coordinator.items.first)

    coordinator.rescan([item.id])
    #expect(item.status == .running)

    // Release the stub's 30-second hold so the task doesn't outlive the test.
    coordinator.cancelAll()
    await waitUntil { coordinator.items.first?.status == .cancelled }
  }

  /**
   Cancelling while a re-scan is in flight must not touch a finished item: the
   probe has no handle to stop, so the run it's re-checking already succeeded
   and stays succeeded.
   */
  @Test
  func `cancel during rescan preserves finished item`() async throws {
    let engine = StubEngine(container: try sampleContainer())
    let coordinator = makeCoordinator(engine)
    await coordinator.add([try SourceFixtures.make("rescan-cancel.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }

    coordinator.startAll()
    await waitUntil { coordinator.items.first?.status == .done && !coordinator.isRunning }
    let item = try #require(coordinator.items.first)
    #expect(coordinator.slimmedCount == 1)

    engine.probeDelay = .milliseconds(200)
    coordinator.rescan([item.id])
    await waitUntil { item.status == .probing }

    coordinator.cancelAll()
    await waitUntil(.seconds(2)) { item.status != .probing }

    #expect(item.status == .done)
    #expect(coordinator.slimmedCount == 1)
  }

  /**
   A re-scan that fails while an item is waiting its turn drops it out of the
   run queue, so freeing a slot doesn't silently run it — and leaves Start
   able to pick it back up once the user asks.
   */
  @Test
  func `start recovers rescanned pending item after failure`() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileA = directory.appending(path: "a.mkv", directoryHint: .notDirectory)
    let fileB = directory.appending(path: "b.mkv", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: fileA)
    try Data("x".utf8).write(to: fileB)

    let engine = StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    let coordinator = makeCoordinator(engine)
    coordinator.maxConcurrent = 1
    await coordinator.add([fileA, fileB])
    await waitUntil {
      coordinator.items.count == 2 && coordinator.items.allSatisfy { $0.status == .ready }
    }
    let itemA = try #require(coordinator.items.first { $0.sourceURL == fileA })
    let itemB = try #require(coordinator.items.first { $0.sourceURL == fileB })

    // A claims the queue's only slot; B is left waiting its turn.
    coordinator.start([itemA.id])
    await waitUntil { itemA.status == .running }
    coordinator.start([itemB.id])
    #expect(itemB.status == .ready)

    // Re-scanning B while it waits fails against a real file, so it settles to
    // `.failed` rather than `.missing`.
    engine.probeFails = true
    coordinator.rescan([itemB.id])
    await waitUntil {
      if case .failed = itemB.status { return true }; return false
    }

    // Freeing the slot must not resurrect B by itself — a failed item is no
    // longer queued, so nothing may run it until the user asks again.
    coordinator.cancel([itemA.id])
    await waitUntil { itemA.status == .cancelled }
    engine.probeFails = false
    await waitUntil(.milliseconds(300)) { itemB.status == .running }
    #expect(itemB.status != .running)

    // Asking again works.
    coordinator.start([itemB.id])
    await waitUntil { itemB.status == .running || itemB.status == .done }
    #expect(itemB.status == .running || itemB.status == .done)

    // Release the stub's 30-second hold so the task doesn't outlive the test.
    coordinator.cancelAll()
    await waitUntil { !coordinator.isRunning }
    try? FileManager.default.removeItem(at: directory)
  }

  /**
   The same pruning seen from the workspace's side. A failed re-scan drops a
   waiting item from the run queue through a path that never pumps, so a queue
   that judged itself busy by whether `pending` was empty would stay busy for
   good — and, since that is how the app knows a run has ended, would never
   announce another run for the rest of the session.
   */
  @Test
  func `a pruned pending item leaves no encode work in flight`() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileA = directory.appending(path: "a.mkv", directoryHint: .notDirectory)
    let fileB = directory.appending(path: "b.mkv", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: fileA)
    try Data("x".utf8).write(to: fileB)
    defer { try? FileManager.default.removeItem(at: directory) }

    let engine = StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    let coordinator = makeCoordinator(engine)
    coordinator.maxConcurrent = 1
    await coordinator.add([fileA, fileB])
    await waitUntil {
      coordinator.items.count == 2 && coordinator.items.allSatisfy { $0.status == .ready }
    }
    let itemA = try #require(coordinator.items.first { $0.sourceURL == fileA })
    let itemB = try #require(coordinator.items.first { $0.sourceURL == fileB })

    // A takes the only slot; B waits its turn, then a failed re-scan prunes it.
    coordinator.start([itemA.id])
    await waitUntil { itemA.status == .running }
    coordinator.start([itemB.id])
    engine.probeFails = true
    coordinator.rescan([itemB.id])
    await waitUntil {
      if case .failed = itemB.status { return true }; return false
    }

    coordinator.cancel([itemA.id])
    await waitUntil { !coordinator.hasEncodeWorkInFlight }
    #expect(!coordinator.hasEncodeWorkInFlight)
  }

  @Test
  func `incompatible when build lacks encoder then recovers`() async throws {
    let capabilities = CapabilityProvider(.videoToolboxOnly)
    let coordinator = makeCoordinator(
      StubEngine(container: try sampleContainer()),
      probeCapabilities: { await capabilities.value }
    )
    await coordinator.add([try SourceFixtures.make("incompat.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)

    // A per-file override transcodes video to an encoder the App Store build lacks.
    item.selection = FileTrackSelection(choices: [
      TrackChoice(
        streamIndex: 0,
        streamType: .video,
        action: .convert(codec: "libx265", options: [])
      )
    ])
    coordinator.ffmpegLocationChanged()
    await waitUntil { isIncompatible(coordinator.items.first?.status) }
    #expect(isIncompatible(item.status))
    #expect(!item.status.isStartable)

    // Switching to a full build clears the flag back to ready.
    await capabilities.set(.full)
    coordinator.ffmpegLocationChanged()
    await waitUntil { coordinator.items.first?.status == .ready }
    #expect(item.status == .ready)
  }

  @Test
  func `overall progress spans the whole queue not just started items`() async throws {
    let coordinator = makeCoordinator(
      StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    )
    await coordinator.add(try SourceFixtures.make((1...4).map { "progress-\($0).mkv" }))
    await waitUntil { coordinator.items.count == 4 }
    let items = coordinator.items

    // Nothing started: the queue is at zero, not undefined.
    for item in items { item.status = .ready }
    #expect(coordinator.overallProgress == 0)

    // One finished and one half-encoded out of four → 1.5 / 4, with the two
    // still queued pulling the fraction down rather than being ignored.
    items[0].status = .done
    items[1].status = .running
    items[1].progress = 0.5
    #expect(coordinator.overallProgress == 0.375)

    // Every item finished reads as complete.
    for item in items { item.status = .done }
    #expect(coordinator.overallProgress == 1)
  }

  @Test
  func `track counts follow the plan until the run reports its own`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try fiveStreamContainer()))
    await coordinator.add([try SourceFixtures.make("tracks.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)
    #expect(item.managedTrackCount == 5)

    // Keep 3 of the 5 tracks (drop one audio and one subtitle) → 2 removed.
    item.selection = dropFrenchTracks()
    #expect(coordinator.tracksRemoved(for: item) == 2)
    #expect(coordinator.outputTrackCount(for: item) == 3)

    // What the finished run recorded supersedes what the plan predicts.
    item.status = .done
    item.tracksRemoved = 1
    #expect(coordinator.outputTrackCount(for: item) == 4)

    // Re-running falls back to the plan, so the last run's count can't outlive it.
    item.status = .running
    #expect(coordinator.outputTrackCount(for: item) == 3)
  }

  @Test
  func `warns when every audio track would be dropped`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try chineseAudioContainer()))
    let file = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: file) }
    await coordinator.ingestAsync([file])
    try await waitUntilSettled(coordinator)
    let item = try #require(coordinator.items.first)

    let warning = try #require(coordinator.audioLossWarning(for: item))
    #expect(warning.contains("Chinese"))
  }

  @Test
  func `does not warn when audio survives`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try sampleContainer()))
    let file = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: file) }
    await coordinator.ingestAsync([file])
    try await waitUntilSettled(coordinator)
    let item = try #require(coordinator.items.first)

    #expect(coordinator.audioLossWarning(for: item) == nil)
  }

  @Test
  func `does not warn when the source has no audio`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try silentContainer()))
    let file = try makeTemporaryMovieFile()
    defer { try? FileManager.default.removeItem(at: file) }
    await coordinator.ingestAsync([file])
    try await waitUntilSettled(coordinator)
    let item = try #require(coordinator.items.first)

    #expect(coordinator.audioLossWarning(for: item) == nil)
  }

  @Test
  func `output size moves from plan to projection to measurement`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try bitRatedContainer()))
    await coordinator.add([try SourceFixtures.make("output-size.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)
    item.sourceByteCount = 66_000_000
    item.selection = dropFrenchTracks()

    // Queued: the source size less the French audio (4.8 MB) and subtitles (15 kB).
    #expect(coordinator.outputSize(for: item) == .estimated(61_185_000))

    // Running: extrapolated from the bytes ffmpeg has written so far.
    item.status = .running
    item.progress = 0.5
    item.writtenByteCount = 30_000_000
    #expect(coordinator.outputSize(for: item) == .estimated(60_000_000))

    // Finished: the size read off the real output file.
    item.status = .done
    item.outputByteCount = 61_400_000
    #expect(coordinator.outputSize(for: item) == .measured(61_400_000))
  }

  @Test
  func `output size is unknown when a dropped track has no bit rate`() async throws {
    let coordinator = makeCoordinator(StubEngine(container: try fiveStreamContainer()))
    await coordinator.add([try SourceFixtures.make("no-bit-rates.mkv")])
    await waitUntil { coordinator.items.first?.status == .ready }
    let item = try #require(coordinator.items.first)
    item.sourceByteCount = 5_000
    item.selection = dropFrenchTracks()

    // The plan is sound, but nothing says how much the dropped tracks weigh.
    #expect(coordinator.outputSize(for: item) == nil)
  }

  private func isIncompatible(_ status: QueueItemState?) -> Bool {
    guard let status else { return false }
    if case .incompatible = status { return true }
    return false
  }
}

/**
 An engine that records each job's input URL, so a test can assert which
 source location the coordinator handed to the child process.
 */
private struct RecordingEngine: ConversionEngineProtocol {
  let container: Container
  let recorder: JobInputRecorder

  func probe(_ url: URL) async throws -> Container {
    await recorder.recordProbe(url)
    return container
  }

  func run(_ job: SlimJob) -> AsyncThrowingStream<JobEvent, any Error> {
    let container = container
    let recorder = recorder
    let input = job.input
    return AsyncThrowingStream { continuation in
      let task = Task {
        await recorder.record(input)
        continuation.yield(.probed(container))
        continuation.yield(.finished)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/**
 Records whether the ingest sheet's state was up at a moment guaranteed to be
 mid-ingest. The coordinator is set after construction because the reading is
 taken from a closure the coordinator itself is built with.
 */
@MainActor
private final class IngestProgressObserver {
  weak var coordinator: QueueCoordinator?
  private(set) var sawSheetState = false

  func recordSheetState() {
    sawSheetState = sawSheetState || coordinator?.ingestProgress != nil
  }
}

/// Captures the URLs an engine was last asked to probe and to run.
private actor JobInputRecorder {
  private(set) var input: URL?
  private(set) var probed: URL?

  func record(_ url: URL) { input = url }
  func recordProbe(_ url: URL) { probed = url }
}

/// A mutable, `Sendable` holder for the capabilities a probe should report.
private actor CapabilityProvider {
  var value: EncoderCapabilities

  init(_ value: EncoderCapabilities) { self.value = value }
  func set(_ value: EncoderCapabilities) { self.value = value }
}
