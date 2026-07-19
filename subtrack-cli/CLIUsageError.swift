import Foundation

/**
 A problem parsing the `subtrack` command line.

 All cases share the headline "Invalid command."; the specific cause is
 carried by ``failureReason``. Every case is resolved the same way, so they
 share a ``recoverySuggestion`` pointing at `--help`.

 Requesting `--help` is normal control flow, not an error; it's modelled by
 ``CommandOptions/ParseResult/help(_:)`` rather than a case here.
 */
enum CLIUsageError: Error {

  /// An option that takes a value was given without one.
  case missingValue(flag: String)

  /// An unrecognized option was supplied.
  case unknownOption(String)

  /// The wrong number of positional arguments was supplied.
  case wrongArgumentCount
}

extension CLIUsageError: LocalizedError {
  var errorDescription: String? {
    String(localized: "Invalid command.")
  }

  var failureReason: String? {
    switch self {
      case .missingValue(let flag):
        String(localized: "The \(flag) option needs a value.")
      case .unknownOption(let option):
        String(localized: "“\(option)” isn’t a known option.")
      case .wrongArgumentCount:
        String(localized: "Expected an input path and an output path.")
    }
  }

  var recoverySuggestion: String? {
    String(localized: "Run “subtrack --help” to see usage.")
  }
}
