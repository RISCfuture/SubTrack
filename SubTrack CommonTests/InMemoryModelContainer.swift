import Foundation
import SwiftData

import SubTrack_Common

extension ModelContainer {
  /**
   The one in-memory container a suite shares across its tests.

   Building a fresh container per test corrupts SwiftData's process-global
   state, so a suite holds a single container and each test clears the models it
   uses. The container is per suite rather than per process because Swift
   Testing runs suites in parallel, and one shared store would have them
   deleting each other's rows mid-test.

   CloudKit is disabled: it cannot back an in-memory store, and its setup blocks
   the thread waiting on operations that never complete in the test host.
   */
  static func inMemory(for models: any PersistentModel.Type...) -> ModelContainer {
    do {
      return try ModelContainer(
        for: Schema(models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      )
    } catch {
      fatalError("Couldn't create the in-memory test ModelContainer: \(error)")
    }
  }
}
