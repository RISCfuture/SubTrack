import Foundation
import Testing

import SubTrack_Common

/**
 What the workspace announces about a run: that a run spanning several queues
 says its piece once, that each run accounts only for the files it touched, and
 that a run the user broke off says nothing at all.
 */
@MainActor
@Suite(.sourceFixtures)
struct QueueCompletionReportingTests {

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
   A workspace whose queues all share `engine` and `governor`, reporting to
   `reporter` — the arrangement ``AppEnvironment`` builds, less the stores.
   */
  private func makeWorkspace(
    engine: any ConversionEngineProtocol,
    governor: EncodeGovernor,
    reporter: SpyReporter
  ) -> Workspace {
    makeWorkspace(governor: governor, reporter: reporter) { _ in engine }
  }

  /**
   A workspace whose queues take their engine by name, so one queue can hold its
   run open while another's runs to the end.
   */
  private func makeWorkspace(
    governor: EncodeGovernor,
    reporter: SpyReporter,
    engineForQueue: @escaping @MainActor (String) -> any ConversionEngineProtocol
  ) -> Workspace {
    Workspace(reporting: reporter) { id, name, sortIndex in
      QueueCoordinator(
        id: id,
        name: name,
        sortIndex: sortIndex,
        engine: engineForQueue(name),
        governor: governor
      )
    }
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

  /// Adds `count` new sources to `coordinator` and waits for their probes to settle.
  private func addItems(
    _ count: Int,
    to coordinator: QueueCoordinator,
    in directory: URL
  ) async throws {
    let existing = coordinator.items.count
    await coordinator.add(try SourceFixtures.make(count, in: directory))
    await waitUntil {
      coordinator.items.count == existing + count
        && coordinator.items.allSatisfy { $0.status != .waiting && $0.status != .probing }
    }
    #expect(coordinator.items.count == existing + count)
  }

  /**
   Two queues sharing one slot means the work interleaves and neither queue
   empties on its own — the case that would report twice if the run were
   tracked per queue rather than across the workspace.
   */
  @Test
  func aRunSpanningTwoQueuesIsAnnouncedOnce() async throws {
    let engine = StubEngine(container: try sampleContainer())
    let reporter = SpyReporter()
    let workspace = makeWorkspace(
      engine: engine,
      governor: EncodeGovernor(limit: 1),
      reporter: reporter
    )
    let directory = try SourceFixtures.makeDirectory()
    let first = workspace.newQueue(name: "First")
    let second = workspace.newQueue(name: "Second")
    try await addItems(3, to: first, in: directory)
    try await addItems(2, to: second, in: directory)

    first.startAll()
    second.startAll()
    await waitUntil { !reporter.summaries.isEmpty }

    #expect(reporter.beginCount == 1)
    #expect(reporter.summaries.count == 1)
    let summary = try #require(reporter.summaries.first)
    #expect(summary.finishedCount == 5)
    #expect(summary.failedCount == 0)
  }

  /**
   Each run accounts for its own files only. The queue still holds the first
   run's finished items, so a summary rolled up from item states rather than
   from the runs themselves would count them a second time.
   */
  @Test
  func aSecondRunCountsOnlyItsOwnFiles() async throws {
    let engine = StubEngine(container: try sampleContainer())
    let reporter = SpyReporter()
    let workspace = makeWorkspace(
      engine: engine,
      governor: EncodeGovernor(limit: 1),
      reporter: reporter
    )
    let directory = try SourceFixtures.makeDirectory()
    let queue = workspace.newQueue(name: "Queue")
    try await addItems(2, to: queue, in: directory)

    queue.startAll()
    await waitUntil { reporter.summaries.count == 1 }

    try await addItems(3, to: queue, in: directory)
    queue.startAll()
    await waitUntil { reporter.summaries.count == 2 }

    #expect(reporter.summaries.map(\.finishedCount) == [2, 3])
  }

  /// A run the user broke off has nothing to congratulate them on.
  @Test
  func aFullyCancelledRunIsNotAnnounced() async throws {
    let engine = StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    let reporter = SpyReporter()
    let workspace = makeWorkspace(
      engine: engine,
      governor: EncodeGovernor(limit: 2),
      reporter: reporter
    )
    let directory = try SourceFixtures.makeDirectory()
    let queue = workspace.newQueue(name: "Queue")
    try await addItems(2, to: queue, in: directory)

    queue.startAll()
    await waitUntil { queue.items.allSatisfy { $0.status == .running } }
    queue.cancelAll()
    await waitUntil { queue.items.allSatisfy { $0.status == .cancelled } }

    #expect(reporter.beginCount == 1)
    #expect(reporter.summaries.isEmpty)
  }

  /**
   A run broken off part-way through says nothing either. The files it got
   through first are no reason to congratulate a user who was sitting there
   stopping it, and counting only what settled would announce them.
   */
  @Test
  func aPartlyCancelledRunIsNotAnnounced() async throws {
    let holding = StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    let finishingEngine = StubEngine(container: try sampleContainer())
    let reporter = SpyReporter()
    let workspace = makeWorkspace(governor: EncodeGovernor(limit: 2), reporter: reporter) { name in
      name == "Holding" ? holding : finishingEngine
    }
    let directory = try SourceFixtures.makeDirectory()
    let held = workspace.newQueue(name: "Holding")
    let finishing = workspace.newQueue(name: "Finishing")
    try await addItems(1, to: held, in: directory)
    try await addItems(1, to: finishing, in: directory)

    // Held open first, so the finishing queue's item settles inside the run
    // rather than ending one of its own.
    held.startAll()
    await waitUntil { held.items.allSatisfy { $0.status == .running } }
    finishing.startAll()
    await waitUntil { finishing.items.allSatisfy { $0.status == .done } }
    held.cancelAll()
    await waitUntil { held.items.allSatisfy { $0.status == .cancelled } }

    #expect(reporter.beginCount == 1)
    // Long enough for the cancelled run to unwind and fire its own hooks.
    await waitUntil(.milliseconds(400)) { !reporter.summaries.isEmpty }
    #expect(reporter.summaries.isEmpty)
  }

  /**
   Deleting the only working queue ends the run without announcing it. The
   coordinator is gone from the workspace before the runs it cancelled have
   unwound, so an unwired teardown both reports a completion nobody waited for
   and lets a departed queue report into the workspace afterwards.
   */
  @Test
  func deletingTheWorkingQueueIsNotAnnounced() async throws {
    let engine = StubEngine(container: try sampleContainer(), holdUntilCancelled: true)
    let reporter = SpyReporter()
    let workspace = makeWorkspace(
      engine: engine,
      governor: EncodeGovernor(limit: 2),
      reporter: reporter
    )
    let directory = try SourceFixtures.makeDirectory()
    let queue = workspace.newQueue(name: "Queue")
    try await addItems(2, to: queue, in: directory)

    queue.startAll()
    await waitUntil { queue.items.allSatisfy { $0.status == .running } }
    workspace.deleteQueue(queue.id)

    // Long enough for the cancelled runs to unwind and fire their own hooks.
    await waitUntil(.milliseconds(400)) { !reporter.summaries.isEmpty }
    #expect(reporter.summaries.isEmpty)
  }
}

/// Records what the workspace reports, for a test to read back.
@MainActor
private final class SpyReporter: QueueCompletionReporting {
  private(set) var beginCount = 0
  private(set) var summaries: [QueueRunSummary] = []

  func queueWorkDidBegin() { beginCount += 1 }

  func queueWorkDidFinish(_ summary: QueueRunSummary) { summaries.append(summary) }
}
