import Foundation
import Testing

import SubTrack_Common

/**
 Records what the coordinator actually asked to be read, and how much of it
 was in flight at once, so a test can tell a shared read from a repeated one.
 */
private actor ReadRecorder {
  private(set) var readFileNames: [String] = []
  private(set) var peakConcurrentReads = 0

  private var inFlight = 0

  func begin(_ url: URL) {
    readFileNames.append(url.lastPathComponent)
    inFlight += 1
    peakConcurrentReads = max(peakConcurrentReads, inFlight)
  }

  func end() {
    inFlight -= 1
  }
}

@Suite
struct ProbeCoordinatorTests {

  // MARK: - Fixtures

  /**
   A folder of `count` real (if tiny) files, deleted when the test ends.
   ``ProbeCoordinator`` keys on each file's size and modification date, so its
   subjects have to exist on disk.
   */
  private func makeSourceFiles(count: Int = 1) throws -> [URL] {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "probe-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try (1...count).map { index in
      let url = folder.appending(path: "source-\(index).mkv")
      try Data("source \(index)".utf8).write(to: url)
      return url
    }
  }

  private func sampleContainer() throws -> Container {
    try JSONDecoder().decode(
      Container.self,
      from: Data(
        """
        {
          "streams": [
            {"index":0,"codec_name":"hevc","codec_type":"video","width":1920,"height":1080,
             "disposition":{"default":1},"tags":{"language":"eng"}}
          ],
          "format":{"filename":"/m.mkv","duration":"60.0","size":"1000"}
        }
        """.utf8
      )
    )
  }

  /**
   A coordinator whose reads are recorded and slow enough to overlap, so
   dedup and the concurrency bound are observable rather than racing.
   */
  private func makeCoordinator(
    limit: Int = ProbeCoordinator.defaultLimit,
    recorder: ReadRecorder,
    readDuration: Duration = .milliseconds(50)
  ) throws -> ProbeCoordinator {
    let container = try sampleContainer()
    return ProbeCoordinator(limit: limit) { url in
      await recorder.begin(url)
      try? await Task.sleep(for: readDuration)
      await recorder.end()
      return container
    }
  }

  // MARK: - Sharing one read

  @Test
  func readsAFileOnceHoweverManyCallersAskAtOnce() async throws {
    let url = try makeSourceFiles()[0]
    let recorder = ReadRecorder()
    let coordinator = try makeCoordinator(recorder: recorder)

    // The burst a dropped folder produces: every caller wants the same file
    // before any read has finished.
    await withTaskGroup(of: Void.self) { group in
      for _ in 1...10 {
        group.addTask { _ = try? await coordinator.container(at: url) }
      }
    }

    #expect(await recorder.readFileNames.count == 1)
  }

  @Test
  func answersALaterCallerFromTheFirstRead() async throws {
    let url = try makeSourceFiles()[0]
    let recorder = ReadRecorder()
    let coordinator = try makeCoordinator(recorder: recorder)

    // The second ask is the one a run makes when it starts on a file the queue
    // already inspected at add time.
    _ = try await coordinator.container(at: url)
    _ = try await coordinator.container(at: url)

    #expect(await recorder.readFileNames.count == 1)
  }

  // MARK: - Staying current

  @Test
  func readsAgainOnceTheFileItselfChanges() async throws {
    let url = try makeSourceFiles()[0]
    let recorder = ReadRecorder()
    let coordinator = try makeCoordinator(recorder: recorder)

    _ = try await coordinator.container(at: url)
    try await Task.sleep(for: .milliseconds(10))
    try Data("source rewritten and longer than before".utf8).write(to: url)
    _ = try await coordinator.container(at: url)

    #expect(await recorder.readFileNames.count == 2)
  }

  @Test
  func invalidateForcesAFreshReadOfAnUnchangedFile() async throws {
    let url = try makeSourceFiles()[0]
    let recorder = ReadRecorder()
    let coordinator = try makeCoordinator(recorder: recorder)

    _ = try await coordinator.container(at: url)
    await coordinator.invalidate(url)
    _ = try await coordinator.container(at: url)

    // What a user-driven re-scan asks for: read it again even though nothing
    // about the file on disk suggests it needs to be.
    #expect(await recorder.readFileNames.count == 2)
  }

  // MARK: - Staying bounded

  @Test
  func neverReadsMoreFilesAtOnceThanTheLimitAllows() async throws {
    let urls = try makeSourceFiles(count: 24)
    let recorder = ReadRecorder()
    let coordinator = try makeCoordinator(limit: 3, recorder: recorder)

    await withTaskGroup(of: Void.self) { group in
      for url in urls {
        group.addTask { _ = try? await coordinator.container(at: url) }
      }
    }

    #expect(await recorder.readFileNames.count == 24)
    #expect(await recorder.peakConcurrentReads <= 3)
    // A bound nothing ever reaches would pass the check above while doing the
    // work one file at a time.
    #expect(await recorder.peakConcurrentReads == 3)
  }
}
