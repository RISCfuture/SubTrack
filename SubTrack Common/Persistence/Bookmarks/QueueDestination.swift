import Foundation
import os

/**
 Shared security-scoped write access to a chosen destination folder, used by
 both the app-default ``OutputDestinationStore`` and each queue's
 ``QueueDestination``. Output *names* come from ``OutputNameFormat``.
 */
enum DestinationAccess {
  /**
   Starts security-scoped access to `destination` itself, the grant that
   covers creating files inside it.
   */
  static func beginAccess(to destination: URL?) -> ScopedAccess {
    guard let destination, destination.startAccessingSecurityScopedResource() else { return .none }
    return ScopedAccess(resolvedURL: destination) {
      destination.stopAccessingSecurityScopedResource()
    }
  }

  /// Whether `folder` lies within (or is) `destination`.
  static func contains(_ folder: URL, in destination: URL?) -> Bool {
    guard let destination else { return false }
    let base = destination.standardizedFileURL.path(percentEncoded: false)
    let target = folder.standardizedFileURL.path(percentEncoded: false)
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return target == base || target.hasPrefix(prefix)
  }
}

/**
 One queue's own output destination: a folder plus its security-scoped
 bookmark, persisted with the queue (not in `UserDefaults`) so each queue can
 send its output somewhere different and restore it across launches.

 The app-wide default that seeds a new queue is ``OutputDestinationStore``;
 the per-item mirror is ``ItemBookmarkStore``, which covers output landing
 outside this folder. ``onChange`` fires when the user picks a new folder so
 the owning queue writes the change through.
 */
@MainActor
@Observable
public final class QueueDestination {
  nonisolated fileprivate static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SubTrack",
    category: "bookmarks"
  )

  /// The current destination folder, if one has been chosen and resolved.
  public private(set) var destinationURL: URL?

  /// Fired when the destination changes so the owning queue can persist it.
  public var onChange: @MainActor () -> Void = {}

  /// The security-scoped bookmark bytes to persist with the queue.
  public var bookmarkData: Data? { bookmark }

  private var bookmark: Data?

  /**
   Creates a destination from a persisted `bookmark` — the seam used by both
   the app-default seed for a new queue and queue hydration.
   */
  public init(bookmark: Data? = nil) {
    load(bookmark)
  }

  /**
   Records a newly chosen destination folder, captures a fresh bookmark to it,
   and notifies the owning queue.
   */
  public func setDestination(_ url: URL) {
    destinationURL = url
    bookmark = SecurityScopedBookmark.data(for: url)
    onChange()
  }

  /**
   Restores a persisted destination `bookmark`, resolving it to a folder URL
   when possible and recreating a stale one. The raw bytes are retained for
   re-persistence even when resolution fails, so the destination round-trips.
   Does not fire ``onChange`` — hydration is not a user edit.
   */
  public func load(_ bookmark: Data?) {
    self.bookmark = bookmark
    guard let bookmark, let resolved = SecurityScopedBookmark.resolve(bookmark) else {
      destinationURL = nil
      return
    }
    destinationURL = resolved.url
    if resolved.isStale { refreshStaleBookmark(for: resolved.url) }
  }

  /**
   Whether writing `outputURL` is covered by this destination's own bookmark —
   true when the file lands in the destination folder or below it. Output
   anywhere else (most commonly alongside its source) needs the queue item's
   own ``QueueItem/outputFolderBookmark`` instead.
   */
  public func covers(_ outputURL: URL) -> Bool {
    DestinationAccess.contains(outputURL.deletingLastPathComponent(), in: destinationURL)
  }

  /**
   Starts security-scoped access to the destination folder and returns a grant
   that stops it when released.
   */
  public func beginAccess() -> ScopedAccess {
    DestinationAccess.beginAccess(to: destinationURL)
  }

  /// Recreates a stale bookmark, holding scoped access for the (re)creation.
  private func refreshStaleBookmark(for url: URL) {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    if !didStart {
      Self.logger.error("\(FileAccessError.accessDenied(url: url).userMessage, privacy: .public)")
    }
    bookmark = SecurityScopedBookmark.data(for: url)
  }
}
