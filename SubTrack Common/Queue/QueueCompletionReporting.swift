public import Foundation

/// What one item's run came to, reported the moment that run settles.
public struct QueueRunOutcome: Sendable {

  /// How the run ended.
  public let result: Result

  /**
   The bytes slimming saved: the source's size less the output's. Negative when
   a transcode grew the file, and `nil` when either size is unknown.
   */
  public let bytesSaved: Int?

  /// The file the run wrote, or `nil` when it wrote none.
  public let outputURL: URL?

  public init(result: Result, bytesSaved: Int?, outputURL: URL?) {
    self.result = result
    self.bytesSaved = bytesSaved
    self.outputURL = outputURL
  }

  /// How a run ended.
  public enum Result: Sendable {
    /// The item was slimmed.
    case finished
    /// The run failed, or the output folder refused it.
    case failed
    /// The user stopped the run.
    case cancelled
  }
}

/**
 What a whole run came to: every queue's encoding taken together, from the first
 item starting to the last one settling.

 Rolled up from the individual ``QueueRunOutcome``s a run produces rather than
 from the queues' items, so a queue's previously-finished files — restored from
 the store, or left over from an earlier run — are never counted again.
 */
public struct QueueRunSummary: Sendable {

  /// How many items the run slimmed.
  public let finishedCount: Int

  /// How many items the run failed to slim.
  public let failedCount: Int

  /**
   The bytes the run saved in total, or `nil` when no finished item knew both
   its source and output sizes.
   */
  public let bytesSaved: Int?

  /// The files the run wrote, for an action that reveals them.
  public let outputURLs: [URL]

  public init(finishedCount: Int, failedCount: Int, bytesSaved: Int?, outputURLs: [URL]) {
    self.finishedCount = finishedCount
    self.failedCount = failedCount
    self.bytesSaved = bytesSaved
    self.outputURLs = outputURLs
  }
}

/**
 Told when the app's encoding starts and stops, so a run the user walked away
 from can announce itself.

 `CompletionNotifier` is the real implementation; a ``Workspace`` built with
 `nil` — every preview, UI test, and unit test — runs as though nothing were
 listening.
 */
@MainActor
public protocol QueueCompletionReporting: AnyObject {
  /**
   Called when the app goes from encoding nothing to encoding something, which
   is the point a notifier can ask for authorization without having troubled a
   user who never runs a queue.
   */
  func queueWorkDidBegin()

  /// Called once every queue's encoding has stopped, with what the run came to.
  func queueWorkDidFinish(_ summary: QueueRunSummary)
}
