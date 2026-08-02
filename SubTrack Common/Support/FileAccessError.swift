import Foundation

/**
 A failure reaching a user-selected file or folder, typically because a
 security-scoped bookmark went stale or access was denied.

 All cases share the headline "Couldn't access that location."; the specific
 cause is carried by ``failureReason``. Every case is user-recoverable, so
 each provides a ``recoverySuggestion``.
 */
public enum FileAccessError: Error, Sendable {

  /// The source file no longer exists at its recorded location.
  case sourceMissing(url: URL)

  /// A security-scoped bookmark couldn't be created or resolved.
  case bookmarkFailed(url: URL)

  /// Access to the file was denied.
  case accessDenied(url: URL)

  /**
   The folder an item's output must be written into can't be created in —
   the sandbox grant covers the source file but not the folder holding it.
   */
  case outputFolderNotWritable(url: URL)

  /// The chosen output folder isn't available.
  case destinationUnavailable
}

extension FileAccessError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t access that location.", bundle: #bundle)
  }

  public var failureReason: String? {
    switch self {
      case .sourceMissing(let url):
        String(localized: "“\(url.lastPathComponent)” is missing or was moved.", bundle: #bundle)
      case .bookmarkFailed(let url):
        String(
          localized: "The saved reference to “\(url.lastPathComponent)” is no longer valid.",
          bundle: #bundle
        )
      case .accessDenied(let url):
        String(
          localized: "SubTrack doesn’t have permission to open “\(url.lastPathComponent)”.",
          bundle: #bundle
        )
      case .outputFolderNotWritable(let url):
        String(
          localized: "SubTrack doesn’t have permission to save into “\(url.lastPathComponent)”.",
          bundle: #bundle
        )
      case .destinationUnavailable:
        String(localized: "The output folder isn’t available.", bundle: #bundle)
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .sourceMissing:
        String(
          localized: "Restore the file, or remove it from the queue and add it again.",
          bundle: #bundle
        )
      case .bookmarkFailed, .accessDenied:
        String(localized: "Add the file to the queue again to restore access.", bundle: #bundle)
      case .outputFolderNotWritable:
        String(
          localized: "Choose an output folder, or add the enclosing folder to the queue.",
          bundle: #bundle
        )
      case .destinationUnavailable:
        String(localized: "Choose the output folder again.", bundle: #bundle)
    }
  }

  /**
   Split by which end of the job went missing: a source the queue can no
   longer reach, or a destination it can no longer write into.
   */
  public var helpAnchor: String? {
    switch self {
      case .sourceMissing, .bookmarkFailed, .accessDenied:
        HelpAnchor.missingSource.rawValue
      case .outputFolderNotWritable, .destinationUnavailable:
        HelpAnchor.settingsGeneral.rawValue
    }
  }
}
