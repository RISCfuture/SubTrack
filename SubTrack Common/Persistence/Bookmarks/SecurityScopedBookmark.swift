import Foundation
import os

/**
 A live grant of security-scoped access to one or more resources, released
 exactly once when the work that requested it finishes. Value-typed and
 `Sendable` so it can be held across an async job and released in a `defer`,
 keeping every `startAccessingSecurityScopedResource` balanced.
 */
public struct ScopedAccess: Sendable {
  /// An empty grant that accesses nothing (the no-op default).
  public static let none = Self {}

  /**
   The URL the grant resolved access to, when it came from a bookmark whose
   path may differ from the caller's own — `nil` for a grant over a URL the
   caller already holds (such as a known output location).
   */
  public let resolvedURL: URL?

  private let stop: @Sendable () -> Void

  /// Creates a grant that reports `resolvedURL` and runs `stop` once on release.
  public init(resolvedURL: URL? = nil, stop: @escaping @Sendable () -> Void) {
    self.resolvedURL = resolvedURL
    self.stop = stop
  }

  /// Stops every access this grant started. Safe to call once.
  public func release() { stop() }
}

/**
 Create/resolve primitives for `.withSecurityScope` bookmarks, shared by the
 stores that persist source and destination access across launches.

 A sandboxed build creates and resolves these `.withSecurityScope`, so the
 resource stays reachable after relaunch; a stale bookmark is reported for the
 caller to recreate. The unsandboxed build has no scope to ask for and writes
 plain bookmarks, which read the same either way — as do the scoped ones the
 sandboxed 1.0 wrote before it.
 */
enum SecurityScopedBookmark {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SubTrack",
    category: "bookmarks"
  )

  /// The sandbox is what gives a scope meaning; outside one there is none to take.
  private static var isScoped: Bool { ProcessInfo.processInfo.isSandboxed }

  static var creationOptions: URL.BookmarkCreationOptions {
    isScoped ? [.withSecurityScope] : []
  }

  static var resolutionOptions: URL.BookmarkResolutionOptions {
    isScoped ? [.withSecurityScope] : []
  }

  /**
   Security-scoped bookmark bytes for `url`, or `nil` when one can't be made
   (for example a synthetic URL outside any granted scope). The caller must
   already hold access to `url` (its transient grant or an active scope).
   */
  static func data(for url: URL) -> Data? {
    do {
      return try url.bookmarkData(
        options: creationOptions,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      logger.error("\(FileAccessError.bookmarkFailed(url: url).userMessage, privacy: .public)")
      return nil
    }
  }

  /**
   Resolves `bookmark` and begins security-scoped access to the resource it
   names, returning the grant plus fresh bytes when the OS reported the
   bookmark stale (the caller stores those in its place). `nil` when the
   bookmark can't be resolved at all.
   */
  static func beginAccess(to bookmark: Data) -> (access: ScopedAccess, refreshed: Data?)? {
    guard let resolved = resolve(bookmark) else { return nil }
    let url = resolved.url
    let didStart = url.startAccessingSecurityScopedResource()
    logDeniedScope(didStart: didStart, to: url)
    let access = ScopedAccess(resolvedURL: url) {
      if didStart { url.stopAccessingSecurityScopedResource() }
    }
    // Recreated under the grant just opened, which is what makes it succeed.
    return (access, resolved.isStale ? data(for: url) : nil)
  }

  /**
   Reports a refused scope grant. Outside the sandbox every grant is refused
   and none is needed, so only a sandboxed build has anything to say.
   */
  static func logDeniedScope(didStart: Bool, to url: URL) {
    guard isScoped, !didStart else { return }
    logger.error("\(FileAccessError.accessDenied(url: url).userMessage, privacy: .public)")
  }

  /**
   Resolves bookmark `data` to its URL, reporting whether the OS considers the
   bookmark stale (and thus in need of recreation). `nil` when it can't be
   resolved at all.
   */
  static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: resolutionOptions,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else { return nil }
    return (url, isStale)
  }
}
