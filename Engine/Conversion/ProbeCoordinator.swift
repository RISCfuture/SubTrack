public import Foundation

/**
 The shared owner of `ffprobe` inspection: it bounds how many probes run at once,
 collapses concurrent probes of one file into a single run, and remembers each
 result so a file is read once however many callers ask about it.

 A whole dropped season arrives as one burst of requests, and a file is asked
 about again when its encode starts. Without somewhere to hold that shared state,
 the first case puts one `ffprobe` process per file on the same disk and the
 second reads every file a second time.

 A remembered container is keyed by the file's size and modification date as well
 as its path, so a source edited on disk is read afresh rather than answered from
 a stale entry. ``invalidate(_:)`` drops an entry outright, which is what a
 user-driven re-scan wants.
 */
public actor ProbeCoordinator {

  /**
   How many probes run at once by default. `ffprobe` spends its time reading,
   not computing, so the useful limit is what keeps one disk busy rather than
   what fills the cores.
   */
  public static let defaultLimit = 4

  /**
   How many containers to remember. Bounds what a long-lived session holds
   after thousands of files have passed through a queue.
   */
  private static let capacity = 512

  private let limiter: ConcurrencyLimiter
  private let readContainer: @Sendable (URL) async throws -> Container

  private var containers: [CacheKey: Container] = [:]
  private var inFlight: [CacheKey: Task<Container, any Error>] = [:]

  /**
   Remembered keys oldest-first, so the cache can shed its stalest entries
   once it reaches ``capacity``.
   */
  private var insertionOrder: [CacheKey] = []

  /**
   Creates a coordinator over some way of reading a file.

   - Parameter limit: How many reads may run at once.
   - Parameter readContainer: Performs one read. Called only when neither a
     remembered container nor an identical read already in flight can answer.
   */
  public init(
    limit: Int = ProbeCoordinator.defaultLimit,
    readContainer: @escaping @Sendable (URL) async throws -> Container
  ) {
    self.limiter = ConcurrencyLimiter(limit: UInt(limit))
    self.readContainer = readContainer
  }

  /**
   The container at `url` — remembered when it has been read before and the
   file hasn't changed since, shared when an identical read is already in
   flight, and read afresh otherwise.
   */
  public func container(at url: URL) async throws -> Container {
    guard let key = CacheKey(url) else { return try await read(url) }
    if let remembered = containers[key] { return remembered }
    if let existing = inFlight[key] { return try await existing.value }

    let task = Task {
      defer { inFlight[key] = nil }
      let container = try await read(url)
      remember(container, for: key)
      return container
    }
    inFlight[key] = task
    return try await task.value
  }

  /**
   Forgets any container remembered for `url`, so the next request reads the
   file again even when nothing about it has changed on disk.
   */
  public func invalidate(_ url: URL) {
    guard let key = CacheKey(url) else { return }
    forget(key)
  }

  private func read(_ url: URL) async throws -> Container {
    try await limiter.withSlot { try await readContainer(url) }
  }

  private func remember(_ container: Container, for key: CacheKey) {
    if containers.updateValue(container, forKey: key) == nil { insertionOrder.append(key) }
    while insertionOrder.count > Self.capacity { forget(insertionOrder[0]) }
  }

  private func forget(_ key: CacheKey) {
    containers[key] = nil
    insertionOrder.removeAll { $0 == key }
  }

  /**
   Identifies a probed file by everything that would make a remembered
   container wrong: where the file is, how big it is, and when it last changed.
   */
  private struct CacheKey: Hashable {
    let path: String
    let byteCount: Int
    let modified: Date

    /**
     `nil` when the file can't be stat'd, which leaves the caller to read
     without remembering rather than key an entry on facts it doesn't have.

     The stat goes through `FileManager` rather than `URL.resourceValues`,
     which answers from values the `URL` cached the first time it was asked —
     so a file rewritten in place would keep producing the key it had before
     it changed, which is the one thing this key exists to notice.
     */
    init?(_ url: URL) {
      let path = url.path(percentEncoded: false)
      guard
        let attributes = try? FileManager.default.attributesOfItem(atPath: path),
        let byteCount = attributes[.size] as? Int,
        let modified = attributes[.modificationDate] as? Date
      else { return nil }
      self.path = path
      self.byteCount = byteCount
      self.modified = modified
    }
  }
}
