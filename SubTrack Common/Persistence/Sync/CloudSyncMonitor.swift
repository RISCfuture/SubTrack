public import CloudKit
import CoreData
import Foundation
import SwiftData

/**
 Everything the app knows about CloudKit: whether the account can sync, when
 the first import has settled, and when another device has written something.

 It is the only type that touches `NSPersistentCloudKitContainer` or
 `CKContainer`. Its consumers see ``PresetSyncCoordinating`` instead, so a
 preview or test can stand in for it without either framework.
 */
@MainActor
@Observable
public final class CloudSyncMonitor: PresetSyncCoordinating {

  /**
   How long to wait for a first import before settling anyway.

   Without this, a store whose import event never arrives — CloudKit throttled,
   the container misconfigured, the network gone — would never seed its starter
   presets, leaving an empty preset list forever. Settling late can duplicate
   the starters, which the store's collapse already repairs; showing nothing is
   not repairable by the user.
   */
  private static let settleTimeout = Duration.seconds(10)

  /// Why presets are not syncing, or `nil` while they are.
  public private(set) var unavailableReason: SyncUnavailableReason?

  private var hasSettled = false
  private var settleHandlers: [@MainActor () -> Void] = []
  private var remoteChangeHandlers: [@MainActor () -> Void] = []

  /**
   Begins watching the CloudKit container.

   The observers are never removed, and deliberately so: ``AppEnvironment``
   builds exactly one monitor and holds it for the process's lifetime, so there
   is no teardown to write. They capture `self` weakly, so nothing here keeps
   the monitor alive and a monitor that somehow outlives its owner degrades to
   a no-op rather than a leak.

   - Parameter containerIdentifier: The ubiquity container backing the presets
     store, as named by its `ModelConfiguration`.
   */
  public init(containerIdentifier: String) {
    observeSyncEvents()
    observeRemoteChanges()
    Task { await self.resolveAccountStatus(for: containerIdentifier) }
    Task { await self.settleAfterTimeout() }
  }

  public func whenInitialImportSettles(_ perform: @escaping @MainActor () -> Void) {
    guard !hasSettled else {
      perform()
      return
    }
    settleHandlers.append(perform)
  }

  public func onRemoteChange(_ perform: @escaping @MainActor () -> Void) {
    remoteChangeHandlers.append(perform)
  }

  /**
   Reports the first import as settled and releases everything waiting on it.
   Repeated calls do nothing, so the timeout and the real event can race
   harmlessly.
   */
  private func settle() {
    guard !hasSettled else { return }
    hasSettled = true
    let handlers = settleHandlers
    settleHandlers = []
    for handler in handlers { handler() }
  }

  /// Settles regardless once ``settleTimeout`` has passed.
  private func settleAfterTimeout() async {
    try? await Task.sleep(for: Self.settleTimeout)
    settle()
  }

  /**
   Maps the iCloud account state onto ``unavailableReason``, and settles
   immediately when no sync is coming — a signed-out user should still get the
   starter presets rather than an empty list.
   */
  private func resolveAccountStatus(for containerIdentifier: String) async {
    let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
    switch status {
      case .available:
        unavailableReason = nil
      case .noAccount:
        unavailableReason = .noAccount
        settle()
      case .restricted:
        unavailableReason = .restricted
        settle()
      default:
        // `couldNotDetermine`, `temporarilyUnavailable`, or a thrown error:
        // sync may still recover on its own, so this says nothing to the user
        // and lets the import event or the timeout settle the wait.
        unavailableReason = nil
    }
  }

  /// Settles on the first finished import, and reports a failed event.
  private func observeSyncEvents() {
    // swiftlint:disable:next discarded_notification_center_observer
    NotificationCenter.default.addObserver(
      forName: NSPersistentCloudKitContainer.eventChangedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
      // An event without an end date is still in flight and says nothing yet.
      guard
        let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
        event.endDate != nil
      else { return }
      let succeeded = event.succeeded
      let isImport = event.type == .import
      Task { @MainActor in self?.handleFinishedEvent(succeeded: succeeded, isImport: isImport) }
    }
  }

  private func handleFinishedEvent(succeeded: Bool, isImport: Bool) {
    unavailableReason = succeeded ? nil : .failed
    if isImport { settle() }
  }

  /// Tells everything waiting that another device's changes have landed.
  private func observeRemoteChanges() {
    // swiftlint:disable:next discarded_notification_center_observer
    NotificationCenter.default.addObserver(
      forName: .NSPersistentStoreRemoteChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        for handler in self.remoteChangeHandlers { handler() }
      }
    }
  }
}
