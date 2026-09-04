import Foundation
import SwiftData
import Testing

import SubTrack_Common

@MainActor
@Suite(.serialized)
struct StoredQueueTests {

  private static let container = ModelContainer.inMemory(
    for: StoredQueue.self,
    StoredQueueItem.self
  )

  private func makeContext() throws -> ModelContext {
    let context = Self.container.mainContext
    try context.delete(model: StoredQueue.self)
    try context.delete(model: StoredQueueItem.self)
    try context.save()
    return context
  }

  private func sampleSnapshot() -> QueueSnapshot {
    QueueSnapshot(
      id: UUID(),
      name: "Movies",
      sortIndex: 2,
      createdAt: Date(timeIntervalSince1970: 1_000_000),
      rules: SlimRules(languages: ["deu", "eng"], includeOtherAudio: true),
      activePresetID: UUID(),
      destinationBookmark: Data([0x01, 0x02, 0x03]),
      items: [
        QueueItemSnapshot(
          sortIndex: 0,
          sourcePath: "/movies/a.mkv",
          sourceBookmark: Data([0xAA]),
          outputPath: "/movies/a.out.mkv",
          customName: "Director’s Cut",
          outputFolderBookmark: Data([0xBB]),
          status: .ready,
          selection: FileTrackSelection(choices: [
            TrackChoice(streamIndex: 0, streamType: .video, action: .copy),
            TrackChoice(
              streamIndex: 1,
              streamType: .audio,
              action: .convert(codec: "aac", options: ["-b:a", "192k"])
            ),
            TrackChoice(streamIndex: 2, streamType: .subtitle, action: .drop)
          ]),
          sourceByteCount: 12_345
        ),
        QueueItemSnapshot(
          sortIndex: 1,
          sourcePath: "/movies/b.mkv",
          outputPath: "/movies/b.out.mkv",
          status: .failed,
          lastError: "boom"
        )
      ]
    )
  }

  @Test
  func `queue round-trips through store`() throws {
    let context = try makeContext()
    let original = sampleSnapshot()

    context.insert(StoredQueue(snapshot: original))
    try context.save()

    let fetched = try #require(
      try context.fetch(FetchDescriptor<StoredQueue>()).first { $0.id == original.id }
    )
    #expect(fetched.asSnapshot == original)
  }

  @Test
  func `items project in sort-index order`() throws {
    let context = try makeContext()
    let queue = StoredQueue(name: "Q", rules: .default)
    // Insert items with sortIndex out of relationship order.
    queue.items = [
      StoredQueueItem(sortIndex: 2, sourcePath: "/c.mkv"),
      StoredQueueItem(sortIndex: 0, sourcePath: "/a.mkv"),
      StoredQueueItem(sortIndex: 1, sourcePath: "/b.mkv")
    ]
    context.insert(queue)
    try context.save()

    let fetched = try #require(try context.fetch(FetchDescriptor<StoredQueue>()).first)
    #expect(fetched.asSnapshot.items.map(\.sourcePath) == ["/a.mkv", "/b.mkv", "/c.mkv"])
  }

  @Test
  func `transient states collapse to ready`() {
    #expect(PersistedItemStatus(.waiting) == .ready)
    #expect(PersistedItemStatus(.probing) == .ready)
    #expect(PersistedItemStatus(.running) == .ready)
    #expect(PersistedItemStatus(.ready) == .ready)
  }

  @Test
  func `failed and incompatible reasons round-trip`() {
    let failed = QueueItemState.failed("disk full")
    let stored = StoredQueueItem(
      persistedStatusRaw: PersistedItemStatus(failed).rawValue,
      lastError: failed.persistedReason
    )
    #expect(stored.persistedStatus == .failed)
    #expect(stored.persistedStatus.state(reason: stored.lastError) == .failed("disk full"))

    let incompatible = QueueItemState.incompatible("no x265")
    #expect(PersistedItemStatus(incompatible) == .incompatible)
    #expect(
      PersistedItemStatus(incompatible).state(reason: incompatible.persistedReason)
        == .incompatible("no x265")
    )
  }
}
