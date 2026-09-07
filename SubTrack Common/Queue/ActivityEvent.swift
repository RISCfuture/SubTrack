public import Foundation

/**
 One line of the Activity Log: something that happened, at the moment it
 happened, kept until the app quits.

 Every event is either the frame of a run or something that went wrong inside
 one. A file that inspects cleanly, encodes, and finishes is not an event —
 the run's closing line carries the count, and the queue window already shows
 what each file came to. That curation is what keeps this window readable
 without a filter.
 */
public struct ActivityEvent: Sendable, Identifiable, Equatable {

  /// Identity for the table, unique per event.
  public let id: UUID

  /// When it happened.
  public let timestamp: Date

  /// What happened.
  public let kind: Kind

  /// The queue it happened in, or empty when it is true of all of them.
  public let queueName: String

  /// The file it happened to, or empty when it is about no single file.
  public let fileName: String

  /**
   Creates an event. The identity and the time are taken here rather than
   passed, so a caller cannot record an event as having happened at a moment
   it did not.

   - Parameter kind: What happened.
   - Parameter queueName: The queue it happened in, or empty for an event true
     of every queue.
   - Parameter fileName: The file it happened to, or empty for an event about
     no single file.
   */
  public init(kind: Kind, queueName: String = "", fileName: String = "") {
    self.id = UUID()
    self.timestamp = .now
    self.kind = kind
    self.queueName = queueName
    self.fileName = fileName
  }

  /// What an event is, and whatever detail it carries.
  public enum Kind: Sendable, Equatable {

    /**
     Encoding began across the app. It carries no count: at the instant the
     first file starts, the rest are still pending, and the closing line
     carries the numbers that turned out to be true.
     */
    case runStarted

    /**
     Encoding stopped, with what the run came to. Recorded even when the user
     cut the run short, which is exactly when they are most likely to come
     looking for what it got through.
     */
    case runFinished(encoded: Int, failed: Int, cancelled: Int, bytesSaved: Int?)

    /// A file's run failed, carrying the message it failed with.
    case fileFailed(String)

    /// A file's source is no longer where it was.
    case sourceMissing

    /// The current FFmpeg can't perform a file's transcode, and why.
    case incompatible(String)

    /// A file that had a problem on the record no longer has one.
    case resolved

    /// A store stopped accepting writes, carrying what it said.
    case notSaving(String)

    /// A store that had stopped accepting writes is taking them again.
    case savingAgain
  }
}

extension ActivityEvent.Kind {

  /**
   How loudly this reads, or `nil` for a line that is nothing to report.

   The same vocabulary the queue window reads from, so a failure is the same
   tier in both places. A run's own lines are unranked however the run went:
   the failures inside it carry their own colour, and colouring the summary
   too would count them twice.
   */
  public var severity: Severity? {
    switch self {
      case .fileFailed, .sourceMissing, .notSaving: .problem
      case .incompatible: .warning
      case .runStarted, .runFinished, .resolved, .savingAgain: nil
    }
  }
}
