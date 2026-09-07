import Foundation
import Testing

import SubTrack_Common

/**
 The log's whole value is what it refuses to write down, so these cover the
 curation rules rather than the recording.
 */
@MainActor
@Suite
struct `Activity log` {

  private let queue = "Movies"

  /**
   The flooding case. A folder of files that inspect, encode, and finish is the
   overwhelmingly common run, and it is worth no lines at all — the run's own
   two lines say it happened and what it came to.
   */
  @Test
  func `a file that behaves is worth no line`() {
    let log = ActivityLog()

    for state in [QueueItemState.ready, .running, .done, .cancelled, .waiting, .probing] {
      log.recordSettled(state, itemID: UUID(), fileName: "Ikiru.mkv", queueName: queue)
    }

    #expect(log.isEmpty)
  }

  @Test
  func `a failure is recorded with the message it failed with`() throws {
    let log = ActivityLog()

    log.recordSettled(
      .failed("ffmpeg exited with code 1"),
      itemID: UUID(),
      fileName: "Rififi.mkv",
      queueName: queue
    )

    let event = try #require(log.events.first)
    #expect(log.events.count == 1)
    #expect(event.kind == .fileFailed("ffmpeg exited with code 1"))
    #expect(event.fileName == "Rififi.mkv")
    #expect(event.kind.severity == .problem)
  }

  /**
   A source's monitor fires on any write to the folder holding it, and every
   FFmpeg change revalidates every file. Both re-report troubles the log is
   already carrying.
   */
  @Test
  func `the same trouble reported twice is written once`() {
    let log = ActivityLog()
    let item = UUID()

    for _ in 0..<5 {
      log.recordSettled(.missing, itemID: item, fileName: "Vanishing Point.mkv", queueName: queue)
    }

    #expect(log.events.count == 1)
  }

  /// A trouble that changes is a different trouble, and says so.
  @Test
  func `a changed message is a new line`() {
    let log = ActivityLog()
    let item = UUID()

    log.recordSettled(.failed("out of space"), itemID: item, fileName: "A.mkv", queueName: queue)
    log.recordSettled(
      .failed("exited with code 1"),
      itemID: item,
      fileName: "A.mkv",
      queueName: queue
    )

    #expect(log.events.count == 2)
  }

  /**
   Without this the reader is left with a red line and no way to know it stopped
   being true — which is the failure the whole window is meant to prevent.
   */
  @Test
  func `a file recovering from a trouble says so`() throws {
    let log = ActivityLog()
    let item = UUID()

    log.recordSettled(.missing, itemID: item, fileName: "Vanishing Point.mkv", queueName: queue)
    log.recordSettled(.ready, itemID: item, fileName: "Vanishing Point.mkv", queueName: queue)

    #expect(log.events.count == 2)
    #expect(try #require(log.events.last).kind == .resolved)
  }

  /// Only a file the log was carrying a trouble for can recover from one.
  @Test
  func `a file that was never in trouble does not recover from one`() {
    let log = ActivityLog()

    log.recordSettled(.ready, itemID: UUID(), fileName: "Ikiru.mkv", queueName: queue)

    #expect(log.isEmpty)
  }

  /// Recovering is a one-off, not a state the file goes on announcing.
  @Test
  func `a recovered file does not go on recovering`() {
    let log = ActivityLog()
    let item = UUID()

    log.recordSettled(.missing, itemID: item, fileName: "V.mkv", queueName: queue)
    log.recordSettled(.ready, itemID: item, fileName: "V.mkv", queueName: queue)
    log.recordSettled(.ready, itemID: item, fileName: "V.mkv", queueName: queue)
    log.recordSettled(.done, itemID: item, fileName: "V.mkv", queueName: queue)

    #expect(log.events.count == 2)
  }

  /// Two files in trouble are two troubles, not one.
  @Test
  func `each file carries its own trouble`() {
    let log = ActivityLog()
    let first = UUID()
    let second = UUID()

    log.recordSettled(.missing, itemID: first, fileName: "A.mkv", queueName: queue)
    log.recordSettled(.missing, itemID: second, fileName: "B.mkv", queueName: queue)
    log.recordSettled(.ready, itemID: first, fileName: "A.mkv", queueName: queue)

    #expect(log.events.count == 3)
    #expect(log.events.filter { $0.kind == .resolved }.count == 1)
  }

  /**
   A run the user cut short is exactly the run they come here to read about, so
   it is recorded however it ended. The finished-run notification deliberately
   says nothing about such a run; the log is the other half of that decision.
   */
  @Test
  func `a run is recorded whatever it came to`() throws {
    let log = ActivityLog()

    log.recordRunStarted()
    log.recordRunFinished(encoded: 4, failed: 1, cancelled: 3, bytesSaved: 1_024)

    #expect(log.events.count == 2)
    #expect(try #require(log.events.first).kind == .runStarted)
    #expect(
      try #require(log.events.last).kind
        == .runFinished(encoded: 4, failed: 1, cancelled: 3, bytesSaved: 1_024)
    )
  }

  @Test
  func `a store failing and recovering is two lines`() throws {
    let log = ActivityLog()

    log.recordCondition(.saveFailed(detail: "disk full"))
    log.recordCondition(nil)

    #expect(log.events.count == 2)
    #expect(try #require(log.events.last).kind == .savingAgain)
    #expect(try #require(log.events.first).kind.severity == .problem)
  }
}
