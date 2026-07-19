#if DEBUG
  import CoreData
  import Foundation
  import SwiftData

  /**
   Creates the CloudKit development schema for the presets store, on demand.

   CloudKit will not sync a record type it has never seen, and the schema is
   created from the model rather than declared in the dashboard. Running this
   is a deliberate act, not something every launch should pay for: it is slow,
   and it is only needed when ``StoredPreset`` changes shape.

   Launch with `-initializeCloudKitSchema`, watch for the log line, then quit.
   Promote the result to production in the CloudKit console before shipping —
   schemas are additive-only from that point, so ``StoredPreset`` cannot be
   reshaped afterward.
   */
  enum CloudKitSchemaInitializer {

    /// Whether this launch asked for the schema to be initialized.
    static var isRequested: Bool {
      ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema")
    }

    /**
     Initializes the schema and unloads the store again.

     Runs before the app's `ModelContainer` exists and tears its own store down
     before returning, so SwiftData and Core Data never both try to sync the
     same file — which is why the whole thing sits in an `autoreleasepool`.
     */
    static func run(configuration: ModelConfiguration) {
      autoreleasepool {
        let description = NSPersistentStoreDescription(url: configuration.url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
          containerIdentifier: ModelContainer.cloudKitContainerIdentifier
        )
        // Load synchronously, so the schema call below cannot outrun the store.
        description.shouldAddStoreAsynchronously = false

        guard
          let model = NSManagedObjectModel.makeManagedObjectModel(for: [StoredPreset.self])
        else {
          return print("CloudKit schema: couldn't build the managed object model.")
        }

        let container = NSPersistentCloudKitContainer(name: "presets", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
          if let error { print("CloudKit schema: couldn't load the store — \(error)") }
        }

        do {
          try container.initializeCloudKitSchema()
          print("CloudKit schema: initialized. Promote it to production before shipping.")
        } catch {
          print("CloudKit schema: initialization failed — \(error)")
        }

        if let store = container.persistentStoreCoordinator.persistentStores.first {
          try? container.persistentStoreCoordinator.remove(store)
        }
      }
    }
  }
#endif
