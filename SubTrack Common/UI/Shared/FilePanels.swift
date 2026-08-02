import AppKit
import UniformTypeIdentifiers

/**
 Thin wrappers around `NSOpenPanel` for adding sources and choosing the
 destination folder.

 Each prompt runs through an overridable handler so a UI test — which can't
 drive an out-of-process `NSOpenPanel` — can substitute fixture URLs (see
 ``UITestHarness``). The defaults are the real panels, so production is
 unchanged.
 */
@MainActor
enum FilePanels {
  /**
   Prompts for one or more video files. Results are filtered by the queue's
   `ingest`, so an unrestricted panel is fine.
   */
  static var chooseMoviesHandler: @MainActor () -> [URL] = runMoviesPanel

  /// Prompts for a folder to add (recursively) to the queue.
  static var chooseFolderHandler: @MainActor () -> URL? = runFolderPanel

  /// Prompts for the destination folder for slimmed output.
  static var chooseDestinationHandler: @MainActor () -> URL? = runDestinationPanel

  static func chooseMovies() -> [URL] { chooseMoviesHandler() }
  static func chooseFolder() -> URL? { chooseFolderHandler() }
  static func chooseDestination() -> URL? { chooseDestinationHandler() }

  private static func runMoviesPanel() -> [URL] {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.prompt = String(localized: "Add", bundle: #bundle)
    panel.message = String(localized: "Choose video files to slim", bundle: #bundle)
    return panel.runModal() == .OK ? panel.urls : []
  }

  private static func runFolderPanel() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.prompt = String(localized: "Add", bundle: #bundle)
    panel.message = String(localized: "Choose a folder of videos", bundle: #bundle)
    return panel.runModal() == .OK ? panel.url : nil
  }

  private static func runDestinationPanel() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Choose", bundle: #bundle)
    panel.message = String(localized: "Choose where slimmed files are saved", bundle: #bundle)
    return panel.runModal() == .OK ? panel.url : nil
  }
}
