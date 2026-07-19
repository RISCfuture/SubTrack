import Foundation

/**
 Why presets are not syncing. Only the unhappy path is modeled, because only
 the unhappy path is shown: a user whose presets sync fine sees nothing.
 */
public enum SyncUnavailableReason: Sendable, Equatable {
  /// No iCloud account is signed in on this Mac.
  case noAccount

  /// iCloud is unavailable under this Mac's restrictions.
  case restricted

  /// iCloud is signed in and permitted, but reported an error.
  case failed
}

extension SyncUnavailableReason {

  /// The one-line explanation shown beneath the preset list.
  public var userMessage: String {
    switch self {
      case .noAccount:
        String(localized: "Presets aren’t syncing — no iCloud account is signed in.")
      case .restricted:
        String(localized: "Presets aren’t syncing — iCloud is unavailable on this Mac.")
      case .failed:
        String(localized: "Presets aren’t syncing — iCloud reported an error.")
    }
  }
}

/**
 The sync facts ``PresetStore`` needs, without the CloudKit machinery that
 supplies them. ``CloudSyncMonitor`` is the real implementation; a store built
 with `nil` — every preview and unit test — behaves as though there were no
 iCloud at all.
 */
@MainActor
public protocol PresetSyncCoordinating: AnyObject {

  /**
   Runs `perform` once the first CloudKit import settles, or immediately when
   there is no usable account and when the wait times out. Runs immediately if
   that has already happened.
   */
  func whenInitialImportSettles(_ perform: @escaping @MainActor () -> Void)

  /// Runs `perform` each time another device's changes reach this store.
  func onRemoteChange(_ perform: @escaping @MainActor () -> Void)
}
