import SwiftUI

/**
 The app's menu-bar commands. Each mirrors a view-model action so the whole
 app is keyboard- and menu-drivable.
 */
struct SubTrackCommands: Commands {
  /**
   Optional so the app shells can pass `nil` in Xcode previews (no environment
   is built there); the menu items are omitted in that case.
   */
  let environment: AppEnvironment?

  var body: some Commands {
    HelpWebCommands()
    if let environment {
      CommandGroup(replacing: .appInfo) {
        AboutMenuButton()
      }
      if let updates = environment.updates {
        CommandGroup(after: .appInfo) {
          UpdateMenuButton(updates: updates)
        }
      }
      QueueFileCommands(environment: environment)
      QueueRunCommands(environment: environment)
      InspectorCommands(ui: environment.ui)
    }
  }
}

/**
 The Help menu's outbound links, beneath the "SubTrack Help" item SwiftUI
 supplies — which AppKit points at the bundled help book once
 `CFBundleHelpBookFolder` and `CFBundleHelpBookName` are set, so nothing here
 replaces `.help`.

 These are the two things the help book deliberately isn't: the current site,
 and somewhere to report a problem. They sit outside the environment check
 because neither needs one.
 */
private struct HelpWebCommands: Commands {
  var body: some Commands {
    CommandGroup(after: .help) {
      Divider()
      Link("SubTrack Website", destination: FeatureFlags.websiteURL)
      Link("Report an Issue…", destination: FeatureFlags.issuesURL)
    }
  }
}

/**
 The File-menu items: creating, renaming, and deleting queues, and adding
 sources to the selected one.
 */
private struct QueueFileCommands: Commands {
  let environment: AppEnvironment

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("New Queue") {
        environment.workspace.newQueue(name: environment.workspace.nextQueueName())
      }
      .keyboardShortcut("n", modifiers: .command)
      Button("Rename Queue…") { beginQueueRename(environment.queue, in: environment) }
      Button("Delete Queue") { requestQueueDeletion(environment.queue, in: environment) }
      Divider()
      Button("Add Files…") { environment.queue.ingest(FilePanels.chooseMovies()) }
        .keyboardShortcut("o", modifiers: .command)
      Button("Add Folder…") {
        if let url = FilePanels.chooseFolder() { environment.queue.ingest([url]) }
      }
      .keyboardShortcut("o", modifiers: [.command, .shift])
    }
  }
}

/// The Queue menu: starting, re-scanning, and clearing the selected queue's work.
private struct QueueRunCommands: Commands {
  let environment: AppEnvironment

  var body: some Commands {
    CommandMenu("Queue") {
      Button("Start All") { queue.startAll() }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!canStartAll)
      Button("Start Selected") { queue.start(queue.selection) }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!canStartSelection)
      Button("Re-scan Selected") { queue.rescan(queue.selection) }
        .disabled(queue.selection.isEmpty)
      Divider()
      Button("Cancel All") { queue.cancelAll() }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(!queue.isRunning)
      Button("Remove Selected") { queue.remove(queue.selection) }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(queue.selection.isEmpty)
      Button("Clear Completed") { queue.clearCompleted() }
    }
  }

  private var queue: QueueCoordinator { environment.queue }

  private var canStartAll: Bool {
    queue.items.contains(where: \.status.isStartable) && !hasOutputNameConflict
  }

  private var canStartSelection: Bool {
    !queue.selection.isEmpty && !hasOutputNameConflict
  }

  /// Two items writing to the same path would destroy a file, so nothing may start.
  private var hasOutputNameConflict: Bool { !queue.outputNameConflicts.isEmpty }
}

/// The View-menu items that show the inspector and choose the tab it shows.
private struct InspectorCommands: Commands {
  let ui: UIState

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button("Toggle Inspector") { ui.inspectorVisible.toggle() }
        .keyboardShortcut("i", modifiers: [.command, .option])
      Button("Inspector: Rules") { ui.inspectorMode = .rules }
        .keyboardShortcut("1", modifiers: [.command, .option])
      Button("Inspector: Override") { ui.inspectorMode = .override }
        .keyboardShortcut("2", modifiers: [.command, .option])
    }
  }
}

/// The custom “About SubTrack” item that opens the app's About window.
private struct AboutMenuButton: View {
  @Environment(\.openWindow)
  private var openWindow

  var body: some View {
    Button("About SubTrack") { openWindow(id: SubTrackWindowID.about) }
  }
}

/**
 The “Check for Updates…” item, shown only in the downloadable build. The
 checker presents its own result window, so the button just starts the check.
 */
private struct UpdateMenuButton: View {
  let updates: any UpdateChecking

  var body: some View {
    Button("Check for Updates…") {
      Task { await updates.checkForUpdatesAndShowUI() }
    }
    .disabled(!updates.canCheckForUpdates)
  }
}
