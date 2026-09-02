import Foundation
import Testing

import SubTrack_Common

/**
 What the workspace announces about a run: that a run spanning several queues
 says its piece once, that each run accounts only for the files it touched, and
 that a run the user broke off says nothing at all.
 */
@MainActor
@Suite
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
    Workspace(reporting: reporter) { id, name, sortIndex in
      QueueCoordinator(
        id: id,
        name: name,
        sortIndex: sortIndex,
        engine: engine,
        governor: governor
      )
    }
  }

  /**
   A directory of the caller's own, so one test's sources can't collide with
   another's and cleanup is a single removal.
   */
  private func makeDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-run-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /**
   Real source files, because ``QueueCoordinator/add(_:)`` monitors each source
   and settles a path that isn't there to `.missing`, which never runs.
   */
  private func makeMovieFiles(_ count: Int, in directory: URL) throws -> [URL] {
    try (0..<count).map { _ in
      let file =
        directory
        .appending(path: "subtrack-\(UUID().uuidString).mkv", directoryHint: .notDirectory)
      try Data("x".utf8).write(to: file)
      return file
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
    await coordinator.add(try makeMovieFiles(count, in: directory))
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
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
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
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
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
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
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
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
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
