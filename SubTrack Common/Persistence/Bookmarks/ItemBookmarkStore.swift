import Foundation
import os

/**
 Persists the per-item security-scoped bookmarks a queued file needs and vends
 balanced access grants for them: one to the source file, one to the folder its
 output is written into.

 A source added by drag, Open, or folder ingest is reachable only for the
 current process unless its transient sandbox grant is captured as a
 `.withSecurityScope` bookmark. ``makeBookmark(for:)`` captures those bookmarks
 while the grant is still active, and the `beginAccess` methods re-resolve them
 (recreating a stale one) for each probe and encode.

 Both are needed because a file-scoped grant reaches only that file: `ffmpeg`
 can read the source through ``beginAccess(to:)`` and still be denied when it
 creates the sibling output. Output inside the queue's chosen destination is
 covered by ``QueueDestination`` instead, which carries its own folder bookmark.
 */
@MainActor
public struct ItemBookmarkStore {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SubTrack",
    category: "bookmarks"
  )

  /// Creates a store. It holds no state; the bookmarks live on the items themselves.
  public init() {}

  /**
   A `.withSecurityScope` bookmark for `url`, or `nil` when one can't be made
   (such as a synthetic test URL, or a folder the app was never granted). Call
   while the transient grant from the drop, open panel, or folder enumeration
   is still active — it can't be minted after relaunch.
   */
  public func makeBookmark(for url: URL) -> Data? {
    SecurityScopedBookmark.data(for: url)
  }

  /**
   Begins security-scoped access to `item`'s source and returns a grant that
   stops it when released.

   Resolves ``QueueItem/sourceBookmark`` (recreating and storing a fresh
   bookmark when the OS reports it stale) and reports the resolved location via
   ``ScopedAccess/resolvedURL``. Falls back to ``ScopedAccess/none`` when the
   item has no bookmark, leaving the caller to use its plain ``QueueItem/sourceURL``.
   */
  public func beginAccess(to item: QueueItem) -> ScopedAccess {
    beginAccess(
      to: item.sourceBookmark,
      describedBy: item.sourceURL,
      storingRefreshed: { item.sourceBookmark = $0 }
    )
  }

  /**
   Begins security-scoped write access to the folder `item`'s output lands in
   and returns a grant that stops it when released. Falls back to
   ``ScopedAccess/none`` when the item has no folder bookmark, leaving the run
   to fail its own writability check with something actionable.
   */
  public func beginAccess(toOutputFolderOf item: QueueItem) -> ScopedAccess {
    beginAccess(
      to: item.outputFolderBookmark,
      describedBy: item.outputURL.deletingLastPathComponent(),
      storingRefreshed: { item.outputFolderBookmark = $0 }
    )
  }

  /**
   Shared resolve-start-refresh for one item bookmark. `location` names the
   resource only for the log line, since an unresolvable bookmark has no URL
   of its own to report.
   */
  private func beginAccess(
    to bookmark: Data?,
    describedBy location: URL,
    storingRefreshed store: (Data) -> Void
  ) -> ScopedAccess {
    guard let bookmark else { return .none }
    guard let began = SecurityScopedBookmark.beginAccess(to: bookmark) else {
      Self.logger.error(
        "\(FileAccessError.bookmarkFailed(url: location).userMessage, privacy: .public)"
      )
      return .none
    }
    if let refreshed = began.refreshed { store(refreshed) }
    return began.access
  }
}
