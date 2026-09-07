import Foundation

/**
 A failure reading or writing SubTrack's stored data (SwiftData and the
 persisted queue/preset blobs).

 Both cases share the headline "Couldn't access your saved data."; the
 specific cause is carried by ``failureReason``. Neither is user-actionable,
 so neither carries a ``recoverySuggestion``: they are logged rather than
 shown, and nothing in the app presents them.
 */
enum PersistenceError: Error, Sendable {

  /// Changes couldn't be saved.
  case saveFailed(detail: String)

  /// Stored data couldn't be loaded.
  case fetchFailed(detail: String)
}

extension PersistenceError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t access your saved data.", bundle: #bundle)
  }

  public var failureReason: String? {
    switch self {
      case .saveFailed(let detail):
        String(localized: "Your changes couldn’t be saved: \(detail)", bundle: #bundle)
      case .fetchFailed(let detail):
        String(localized: "Saved data couldn’t be loaded: \(detail)", bundle: #bundle)
    }
  }
}
