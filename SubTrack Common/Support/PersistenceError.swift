import Foundation

/**
 A failure reading or writing SubTrack's stored data (SwiftData and the
 persisted queue/preset blobs).

 All cases share the headline "Couldn't access your saved data."; the
 specific cause is carried by ``failureReason``. None are user-actionable, so
 they carry no ``recoverySuggestion`` — they should be logged rather than
 prompt the user to act.
 */
enum PersistenceError: Error, Sendable {

  /// The data store couldn't be opened.
  case storeUnavailable(detail: String)

  /// Changes couldn't be saved.
  case saveFailed(detail: String)

  /// Stored data couldn't be loaded.
  case fetchFailed(detail: String)

  /// Stored data was present but couldn't be read, and was reset to a default.
  case dataCorrupt(detail: String)
}

extension PersistenceError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t access your saved data.", bundle: #bundle)
  }

  public var failureReason: String? {
    switch self {
      case .storeUnavailable(let detail):
        String(localized: "The data store couldn’t be opened: \(detail)", bundle: #bundle)
      case .saveFailed(let detail):
        String(localized: "Your changes couldn’t be saved: \(detail)", bundle: #bundle)
      case .fetchFailed(let detail):
        String(localized: "Saved data couldn’t be loaded: \(detail)", bundle: #bundle)
      case .dataCorrupt(let detail):
        String(
          localized: "Some saved data was unreadable and was reset: \(detail)",
          bundle: #bundle
        )
    }
  }
}
