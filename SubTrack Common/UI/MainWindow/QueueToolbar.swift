import SwiftUI

/// The window toolbar: add, run controls, and trailing controls.
struct QueueToolbar: ToolbarContent {
  @Environment(AppEnvironment.self)
  private var env

  var body: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Menu {
        Button("Add Files…") { env.queue.ingest(FilePanels.chooseMovies()) }
        Button("Add Folder…") { if let url = FilePanels.chooseFolder() { env.queue.ingest([url]) } }
      } label: {
        Label("Add", systemImage: "plus")
      } primaryAction: {
        env.queue.ingest(FilePanels.chooseMovies())
      }
      .accessibilityIdentifier("toolbar.add")
    }

    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        env.queue.startAll()
      } label: {
        Label("Start All", systemImage: "play.fill")
      }
      .disabled(!canStart)
      .accessibilityIdentifier("toolbar.startAll")

      Button {
        env.queue.cancelAll()
      } label: {
        Label("Cancel", systemImage: "stop.fill")
      }
      .disabled(!env.queue.isRunning)
      .accessibilityIdentifier("toolbar.cancel")
    }

    ToolbarItem(placement: .automatic) {
      PresetMenu(accessibilityIdentifier: "toolbar.presetMenu")
    }

    ToolbarItem(placement: .automatic) {
      Button {
        env.ui.inspectorVisible.toggle()
      } label: {
        Label("Toggle Inspector", systemImage: "sidebar.trailing")
      }
      .accessibilityIdentifier("toolbar.toggleInspector")
    }
  }

  private var canStart: Bool {
    env.queue.items.contains(where: \.status.isStartable) && env.queue.outputNameConflicts.isEmpty
  }
}
