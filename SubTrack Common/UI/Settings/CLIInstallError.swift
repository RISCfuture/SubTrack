import Foundation

/**
 A failure installing the bundled `subtrack` command-line tool into a folder
 on the user's `PATH`.

 All cases share the headline "Couldn't install the command-line tool."; the
 specific cause is carried by ``failureReason``. Only ``permissionDenied``
 is user-actionable and carries a ``recoverySuggestion``.
 */
enum CLIInstallError: Error, Sendable {

  /// This build doesn't bundle the `subtrack` executable.
  case toolMissingFromBundle

  /// The executable couldn't be copied into place.
  case copyFailed(detail: String)

  /// The chosen destination isn't writable without elevated privileges.
  case permissionDenied(path: String)
}

extension CLIInstallError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t install the command-line tool.", bundle: #bundle)
  }

  public var failureReason: String? {
    switch self {
      case .toolMissingFromBundle:
        String(localized: "This build doesn’t include the subtrack tool.", bundle: #bundle)
      case .copyFailed(let detail):
        String(localized: "The tool couldn’t be copied: \(detail)", bundle: #bundle)
      case .permissionDenied(let path):
        String(localized: "SubTrack doesn’t have permission to write to \(path).", bundle: #bundle)
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .permissionDenied:
        String(
          localized: "Choose a folder you can write to, or authenticate to install for all users.",
          bundle: #bundle
        )
      default:
        nil
    }
  }

  /**
   ``toolMissingFromBundle`` means this copy of the app was built wrong, which
   no amount of documentation helps with; the other two are the ordinary
   install troubles the manual walks through.
   */
  public var helpAnchor: String? {
    switch self {
      case .toolMissingFromBundle: nil
      case .copyFailed, .permissionDenied: HelpAnchor.cliInstall.rawValue
    }
  }
}
