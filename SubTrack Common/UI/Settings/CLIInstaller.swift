import AppKit
import Foundation

/**
 Installs the bundled `subtrack` command-line tool onto the user's `PATH` from
 Settings ▸ CLI, and reports whether it is currently installed.

 The app is sandboxed, so the copy destination must be user-selected through a
 panel; the chosen folder is remembered as an app-scope security-scoped
 bookmark so the status survives relaunch. When the destination isn't writable
 (the common `/usr/local/bin` case) the installer falls back to surfacing a
 `sudo cp` command for the user to run in Terminal instead.
 */
@MainActor
@Observable
final class CLIInstaller {
  /**
   The default folder offered in the install panel and used in the
   escape-hatch command.
   */
  nonisolated static let defaultDestination = URL(
    fileURLWithPath: "/usr/local/bin",
    isDirectory: true
  )

  /// The current install status, updated by ``install()`` and ``refreshStatus()``.
  internal(set) var status: Status = .unknown

  /// The embedded CLI shipped in the app bundle's Resources, if present.
  let embeddedCLI_URL: URL? = Bundle.main.url(forResource: "subtrack", withExtension: nil)

  private let defaultsKey = "cli.installFolder"
  private let defaults: UserDefaults

  /**
   Creates an installer that remembers its install folder in `defaults`,
   which a test points at its own suite.
   */
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /**
   The Terminal escape-hatch command that copies `source` to
   `<destinationDirectory>/subtrack`, quoting both paths so embedded spaces
   (as in an app-bundle Resources path) survive the shell.
   */
  nonisolated static func installCommand(
    source: URL,
    destinationDirectory: URL = defaultDestination
  ) -> String {
    let destination = destinationDirectory.appendingPathComponent("subtrack")
    return
      "sudo cp \"\(source.path(percentEncoded: false))\" \"\(destination.path(percentEncoded: false))\""
  }

  /**
   Prompts for an install folder, copies the embedded CLI there with mode
   `0o755`, and remembers the folder so the status survives relaunch.

   A permission failure (the not-writable destination case) switches to
   ``Status/needsElevation(command:)`` so the UI can offer the `sudo`
   command; any other failure becomes ``Status/failed(_:)``.
   */
  func install() {
    guard let source = embeddedCLI_URL else {
      status = .failed(CLIInstallError.toolMissingFromBundle.userMessage)
      return
    }
    guard let folder = chooseInstallFolder() else { return }

    let didStart = folder.startAccessingSecurityScopedResource()
    defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

    do {
      let destination = try copyCLI(from: source, into: folder)
      persistInstallFolder(folder)
      status = .installed(path: destination.path(percentEncoded: false))
    } catch {
      if case .permissionDenied = error {
        status = .needsElevation(
          command: Self.installCommand(source: source, destinationDirectory: folder)
        )
      } else {
        status = .failed(error.userMessage)
      }
    }
  }

  /**
   Resolves the remembered install folder and reports whether `subtrack` is
   still present there. Called when the CLI settings tab appears.
   */
  func refreshStatus() {
    guard
      let data = defaults.data(forKey: defaultsKey),
      let resolved = SecurityScopedBookmark.resolve(data)
    else {
      status = .notInstalled
      return
    }

    let folder = resolved.url
    let didStart = folder.startAccessingSecurityScopedResource()
    defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

    let binary = folder.appendingPathComponent("subtrack")
    if FileManager.default.fileExists(atPath: binary.path(percentEncoded: false)) {
      if resolved.isStale { persistInstallFolder(folder) }
      status = .installed(path: binary.path(percentEncoded: false))
    } else {
      status = .notInstalled
    }
  }

  /// Reveals the installed binary in Finder, if the current status knows its path.
  func revealInFinder() {
    guard case .installed(let path) = status else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }

  /**
   Copies the default-destination install command to the pasteboard — the
   always-available escape hatch for users who prefer Terminal.
   */
  func copyInstallCommand() {
    guard let source = embeddedCLI_URL else { return }
    copyToPasteboard(Self.installCommand(source: source))
  }

  /// Places `command` on the general pasteboard for the callout's Copy button.
  func copyToPasteboard(_ command: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
  }

  private func chooseInstallFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.directoryURL = Self.defaultDestination
    panel.prompt = String(localized: "Install")
    panel.message = String(localized: "Choose a folder on your PATH to install subtrack")
    return panel.runModal() == .OK ? panel.url : nil
  }

  /**
   Copies the CLI into `folder` as `subtrack`, replacing any existing copy and
   marking it executable. Returns the destination URL.

   A permission failure surfaces as ``CLIInstallError/permissionDenied(path:)``
   so the caller can offer the `sudo` escape hatch; any other filesystem
   failure becomes ``CLIInstallError/copyFailed(detail:)``.
   */
  private func copyCLI(from source: URL, into folder: URL) throws(CLIInstallError) -> URL {
    let destination = folder.appendingPathComponent("subtrack")
    let destinationPath = destination.path(percentEncoded: false)
    let fileManager = FileManager.default
    do {
      if fileManager.fileExists(atPath: destinationPath) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.copyItem(at: source, to: destination)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationPath)
    } catch let error where error.isPermissionDenied {
      throw CLIInstallError.permissionDenied(path: destinationPath)
    } catch {
      throw CLIInstallError.copyFailed(detail: String(describing: error))
    }
    return destination
  }

  private func persistInstallFolder(_ folder: URL) {
    guard let bookmark = SecurityScopedBookmark.data(for: folder) else { return }
    defaults.set(bookmark, forKey: defaultsKey)
  }

  /// Where the install flow reached and what to offer the user next.
  enum Status: Sendable, Equatable {
    /// Status hasn't been resolved yet (before the first ``refreshStatus()``).
    case unknown
    /// No remembered install, or the remembered binary is gone.
    case notInstalled
    /// Installed and present at `path`.
    case installed(path: String)
    /// The chosen folder isn't writable; run `command` with `sudo` instead.
    case needsElevation(command: String)
    /// The install failed for a reason other than permissions.
    case failed(String)
  }
}

private extension Error {
  /**
   Whether this filesystem error is a permission denial — the not-writable
   destination case — by Cocoa error code or an underlying POSIX `errno`.
   */
  var isPermissionDenied: Bool {
    let error = self as NSError
    if error.domain == CocoaError.errorDomain,
      error.code == CocoaError.fileWriteNoPermission.rawValue
    {
      return true
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return underlying.isPermissionDenied
    }
    return error.domain == NSPOSIXErrorDomain
      && (error.code == Int(EPERM) || error.code == Int(EACCES))
  }
}
