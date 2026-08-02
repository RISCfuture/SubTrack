import Foundation

/**
 Persists the user's chosen output folder as a bookmark.

 The bookmark is security-scoped in the sandboxed build, so the folder stays
 writable across launches; a stale bookmark is transparently recreated. This
 is the app-wide default that seeds each new queue's own ``QueueDestination``,
 which is what a run actually takes write access from.
 */
@MainActor
@Observable
public final class OutputDestinationStore {
  /// The current destination folder, if one has been chosen and resolved.
  public private(set) var destinationURL: URL?

  /**
   The persisted destination bookmark bytes, used to seed a new queue's own
   ``QueueDestination`` from this app-wide default.
   */
  public var bookmarkData: Data? { defaults.data(forKey: defaultsKey) }

  private let defaultsKey = "outputDestinationBookmark"
  private let defaults: UserDefaults

  /**
   Creates a store over `defaults`, which a test points at its own suite,
   and resolves the destination its bookmark names.
   */
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    resolveBookmark()
  }

  /// Records a newly chosen destination folder and persists a bookmark to it.
  public func setDestination(_ url: URL) {
    destinationURL = url
    persistBookmark(for: url)
  }

  private func resolveBookmark() {
    guard
      let data = defaults.data(forKey: defaultsKey),
      let resolved = SecurityScopedBookmark.resolve(data)
    else { return }
    destinationURL = resolved.url
    if resolved.isStale { refreshStaleBookmark(for: resolved.url) }
  }

  /// Recreates a stale bookmark, holding scoped access for the (re)creation.
  private func refreshStaleBookmark(for url: URL) {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    SecurityScopedBookmark.logDeniedScope(didStart: didStart, to: url)
    persistBookmark(for: url)
  }

  private func persistBookmark(for url: URL) {
    guard let bookmark = SecurityScopedBookmark.data(for: url) else { return }
    defaults.set(bookmark, forKey: defaultsKey)
  }
}
