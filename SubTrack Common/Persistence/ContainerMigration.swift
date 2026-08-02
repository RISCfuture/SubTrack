import Foundation
import os

/**
 Moves a sandboxed release's data out of its app container.

 The downloadable build was sandboxed through 1.0, so its defaults and
 SwiftData stores live under `~/Library/Containers/<bundle id>/Data`. Without
 the sandbox those same lookups resolve to `~/Library`, which would greet an
 upgrading user with an empty app. This copies the container's contents across
 once, on first launch of an unsandboxed build, and leaves the container in
 place so a downgrade still finds its data.
 */
public enum ContainerMigration {
  private static let completionKey = "didMigrateSandboxContainer"

  private static let log = Logger(subsystem: "SubTrack", category: "ContainerMigration")

  /// The 1.0 container, when this Mac still has one.
  private static var legacyContainerDirectory: URL? {
    guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
    let container = URL.homeDirectory
      .appending(path: "Library/Containers", directoryHint: .isDirectory)
      .appending(path: bundleID, directoryHint: .isDirectory)
      .appending(path: "Data", directoryHint: .isDirectory)
    return FileManager.default.fileExists(atPath: container.path(percentEncoded: false))
      ? container : nil
  }

  /**
   Copies the container's stores and defaults across, once. Does nothing when
   this build is sandboxed (the container is still where the data belongs),
   when a previous launch already migrated, or when there is no container to
   migrate from.

   Call before anything reads `UserDefaults` or opens the model container —
   the copy has to be in place first, so this runs synchronously.
   */
  public static func run(defaults: UserDefaults = .standard) {
    guard !ProcessInfo.processInfo.isSandboxed,
      !defaults.bool(forKey: completionKey),
      let container = legacyContainerDirectory
    else { return }

    do {
      try copyStores(
        from: container.appending(path: "Library/Application Support", directoryHint: .isDirectory),
        to: FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
      )
      adoptDefaults(from: container, into: defaults)
      defaults.set(true, forKey: completionKey)
      log.notice("Migrated app data out of the sandbox container.")
    } catch {
      // Left unmarked so the next launch tries again; the app still opens,
      // on whatever the new locations already hold.
      log.error("Couldn't migrate the sandbox container: \(error.localizedDescription)")
    }
  }

  /**
   Copies every store `source` holds — SwiftData's `.store` files and the
   CloudKit sidecars beside them — into `destination`.

   Anything already at the destination is left as it is, so a half-finished
   migration resumes rather than overwrites, and the symlinks macOS plants in
   a container's Application Support (pointing back into the real one) are
   skipped rather than followed.
   */
  static func copyStores(from source: URL, to destination: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return }

    for item in try fileManager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: [.isSymbolicLinkKey],
      options: []
    ) {
      let isSymbolicLink = try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
      let target = destination.appending(path: item.lastPathComponent)
      guard isSymbolicLink != true,
        !fileManager.fileExists(atPath: target.path(percentEncoded: false))
      else { continue }
      try fileManager.copyItem(at: item, to: target)
    }
  }

  /**
   Adopts the container's preferences, leaving any key this domain already
   holds alone — the unsandboxed domain wins where the two disagree.
   */
  private static func adoptDefaults(from container: URL, into defaults: UserDefaults) {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    let plist = container.appending(
      path: "Library/Preferences/\(bundleID).plist",
      directoryHint: .notDirectory
    )
    guard let data = try? Data(contentsOf: plist),
      let stored = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return }
    for (key, value) in stored where defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
    }
  }
}
