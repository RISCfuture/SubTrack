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

  /**
   The help-book topic explaining this failure, for the errors the book has a
   page about.

   Bridging through `NSError` picks up `LocalizedError`'s `helpAnchor` — the
   slot Foundation already reserves for exactly this, and the one AppKit reads
   to put a Help button on a presented error — so an error says which page
   explains it in the same place it says what went wrong.

   `nil` for anything the book doesn't cover, which is most of them. Offering
   help that lands on a general page is worse than offering none.
   */
  var helpTopic: HelpAnchor? {
    (self as NSError).helpAnchor.flatMap(HelpAnchor.init(rawValue:))
  }
}
