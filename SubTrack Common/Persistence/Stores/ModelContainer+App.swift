import Foundation
public import SwiftData

extension ModelContainer {
  /**
   The one in-memory container shared by every preview that builds an
   environment. Lazily created, so a non-preview run never allocates it.
   */
  private static let sharedPreviewContainer = makeContainer(inMemory: true)

  private static let containerCreationAttempts = 5

  /// The ubiquity container the presets store syncs through, as both entitlements declare it.
  static let cloudKitContainerIdentifier = "iCloud.codes.tim.SubTrack"

  /**
   The app's SwiftData container, holding the preset, queue, and queue-item
   models.

   Inside an Xcode preview it returns a single shared in-memory container: the
   on-disk store can't be created in the preview sandbox, and — critically —
   SwiftData traps (`EXC_BREAKPOINT`) if more than one container is created for
   the same models in one process. A preview is hosted in the app, so the app
   shell and every preview must resolve to the *same* container.
   */
  public static func subTrackApp() -> ModelContainer {
    AppEnvironment.isRunningInXcodePreview ? sharedPreviewContainer : makeContainer(inMemory: false)
  }

  #if DEBUG
    /**
     A fresh in-memory container for a UI-test launch, so tests never touch the
     user's real store. Each launch is a separate process, so a new container
     each time is correct — there is no live preview host to collide with.
     */
    static func subTrackUITests() -> ModelContainer { makeContainer(inMemory: true) }
  #endif

  /**
   The presets store's configuration — CloudKit-backed unless it is in memory.

   CloudKit can't back an in-memory store, and its setup blocks the main
   thread waiting on operations that fail in the sandboxed preview/JIT host —
   which surfaces as a `loadIssueModelContainer` hang. Disable it for the
   in-memory (preview/test) configuration.
   */
  private static func presetsConfiguration(inMemory: Bool) -> ModelConfiguration {
    ModelConfiguration(
      "presets",
      schema: Schema([StoredPreset.self]),
      isStoredInMemoryOnly: inMemory,
      cloudKitDatabase: inMemory ? .none : .private(cloudKitContainerIdentifier)
    )
  }

  private static func makeContainer(inMemory: Bool) -> ModelContainer {
    #if DEBUG
      if !inMemory && CloudKitSchemaInitializer.isRequested {
        CloudKitSchemaInitializer.run(configuration: presetsConfiguration(inMemory: false))
      }
    #endif
    let presets = presetsConfiguration(inMemory: inMemory)
    // Queues stay on this Mac. Their security-scoped bookmarks and absolute
    // paths mean nothing on another one, so a synced queue would arrive as a
    // list of broken items.
    let local = ModelConfiguration(
      "local",
      schema: Schema([StoredQueue.self, StoredQueueItem.self]),
      isStoredInMemoryOnly: inMemory,
      cloudKitDatabase: .none
    )
    // Creating the container intermittently fails in the Xcode preview JIT host;
    // a retry clears it. (Outside previews this succeeds on the first attempt.)
    var lastError: (any Error)?
    for _ in 0..<containerCreationAttempts {
      do {
        return try ModelContainer(
          for: Schema([StoredPreset.self, StoredQueue.self, StoredQueueItem.self]),
          configurations: presets,
          local
        )
      } catch {
        lastError = error
      }
    }
    fatalError("Could not create the SubTrack ModelContainer: \(String(describing: lastError))")
  }
}
