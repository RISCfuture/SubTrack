public import Foundation
public import Observation

/**
 What happened during this run of the app, newest last.

 The window this feeds exists to answer one question — *what went wrong while
 I was away?* — so the log records the frame of a run and the troubles inside
 it, and nothing else. A file that inspects, encodes, and finishes writes no
 line at all: the run's closing line carries the counts, and the queue window
 already shows what each file came to.

 That curation is the whole design. Recording every state change and then
 offering a filter would be the same window with more work in front of the
 reader; a log that needs filtering to be readable recorded the wrong things.
 A clean run of three hundred files is two lines here.

 Nothing is written to disk. The log answers for the session it belongs to,
 which is the session that did the encoding.
 */
@MainActor
@Observable
public final class ActivityLog {

  /**
   The most events kept, oldest dropped past it. Far above what a curated log
   reaches — it exists so a pathological run cannot grow the app's memory
   without bound, not as a retention policy anyone is meant to notice.
   */
  private static let capacity = 2_000

  /// Everything recorded this session, oldest first.
  public private(set) var events: [ActivityEvent] = []

  /**
   The problem each file currently has on the record, so the same trouble
   reported twice is written once and so a file recovering can be told apart
   from a file that was never in trouble.
   */
  private var recordedProblems: [UUID: QueueItemState] = [:]

  #if DEBUG
    /**
     Stops the log taking anything further, so a seeded account cannot be
     disturbed by a probe or a revalidation settling behind the picture being
     taken. Compiled out of release builds; see ``UITestHarness``.
     */
    private var isSealedForTesting = false
  #endif

  /// Whether anything has been recorded, so the window can offer an empty state.
  public var isEmpty: Bool { events.isEmpty }

  /// Creates an empty log.
  public init() {}

  /// The line a settled state deserves, or `nil` when it is not a problem.
  private static func problemKind(for state: QueueItemState) -> ActivityEvent.Kind? {
    switch state {
      case .failed(let message): .fileFailed(message)
      case .missing: .sourceMissing
      case .incompatible(let reason): .incompatible(reason)
      case .waiting, .probing, .ready, .running, .done, .cancelled: nil
    }
  }

  /**
   Records a file settling, when that settling is news.

   News is a problem the log is not already carrying for this file, or the end
   of one it is. Everything else — a file going ready, encoding, or finishing —
   returns without a word, which is what keeps a three-hundred-file run from
   burying the one line that matters.

   - Parameter state: The state the file settled into.
   - Parameter itemID: The file's identity, which is how a later recovery is
     matched to the problem it ends.
   - Parameter fileName: The file's name, as the log will show it.
   - Parameter queueName: The queue the file is in.
   */
  public func recordSettled(
    _ state: QueueItemState,
    itemID: UUID,
    fileName: String,
    queueName: String
  ) {
    guard let kind = Self.problemKind(for: state) else {
      resolveProblem(itemID: itemID, fileName: fileName, queueName: queueName)
      return
    }
    guard recordedProblems[itemID] != state else { return }
    recordedProblems[itemID] = state
    append(.init(kind: kind, queueName: queueName, fileName: fileName))
  }

  #if DEBUG
    /// Replaces the log with a fixed account and seals it, for the Help book's picture.
    public func sealWithEventsForTesting(_ events: [ActivityEvent]) {
      self.events = events
      isSealedForTesting = true
    }
  #endif

  /**
   Records encoding starting.

   - Parameter queueName: The queue the run is in, or how many when it spans
     several. A run is app-wide — the concurrency limit is — but it is not
     therefore about every queue, and a line claiming queues that took no part
     in it would be false.
   */
  public func recordRunStarted(in queueName: String) {
    append(.init(kind: .runStarted, queueName: queueName))
  }

  /**
   Records encoding stopping, with what the run came to.

   - Parameter encoded: How many files the run slimmed.
   - Parameter failed: How many it failed to slim.
   - Parameter cancelled: How many the user stopped.
   - Parameter bytesSaved: What the run saved in total, or `nil` when no
     finished file knew both its sizes.
   - Parameter queueName: The queue the run was in, or how many when it spanned
     several.
   */
  public func recordRunFinished(
    encoded: Int,
    failed: Int,
    cancelled: Int,
    bytesSaved: Int?,
    in queueName: String
  ) {
    append(
      .init(
        kind: .runFinished(
          encoded: encoded,
          failed: failed,
          cancelled: cancelled,
          bytesSaved: bytesSaved
        ),
        queueName: queueName
      )
    )
  }

  /**
   Records a store starting or stopping to accept writes.

   ``PersistenceHealth`` reports only the edges, so a store failing on every
   write for a minute is one line here and not four hundred.

   - Parameter failure: What the store said, or `nil` when it is writing again.
   */
  public func recordCondition(_ failure: PersistenceError?) {
    guard let failure else {
      append(.init(kind: .savingAgain))
      return
    }
    append(.init(kind: .notSaving(failure.userMessage)))
  }

  /// Notes that a file's recorded trouble is over, saying so only if it had one.
  private func resolveProblem(itemID: UUID, fileName: String, queueName: String) {
    guard recordedProblems.removeValue(forKey: itemID) != nil else { return }
    append(.init(kind: .resolved, queueName: queueName, fileName: fileName))
  }

  private func append(_ event: ActivityEvent) {
    #if DEBUG
      if isSealedForTesting { return }
    #endif
    events.append(event)
    if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
  }
}
