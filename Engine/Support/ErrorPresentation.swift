import Foundation

extension Error {
  /**
   A single user-facing string that combines the error's headline
   description with its failure reason and recovery suggestion when present.

   Bridging through `NSError` picks up `LocalizedError`'s `errorDescription`,
   `failureReason`, and `recoverySuggestion`, so any `LocalizedError` renders
   consistently and a plain Foundation error still yields its system message.
   */
  public var userMessage: String {
    let error = self as NSError
    var parts = [error.localizedDescription]
    if let reason = error.localizedFailureReason { parts.append(reason) }
    if let suggestion = error.localizedRecoverySuggestion { parts.append(suggestion) }
    return parts.joined(separator: " ")
  }
}
