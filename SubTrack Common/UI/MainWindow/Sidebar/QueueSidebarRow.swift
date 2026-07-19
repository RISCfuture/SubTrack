import SwiftUI

/**
 One queue's row: its name (or an inline rename field) and a trailing aggregate
 status indicator.
 */
struct QueueSidebarRow: View {
  @Environment(AppEnvironment.self)
  private var env
  let coordinator: QueueCoordinator
  @State private var draftName = ""
  @FocusState private var fieldFocused: Bool

  var body: some View {
    HStack {
      if isRenaming {
        TextField("Queue name", text: $draftName)
          .textFieldStyle(.roundedBorder)
          .focused($fieldFocused)
          .onSubmit(commit)
          .onExitCommand(perform: cancel)
          .accessibilityIdentifier("sidebar.renameField")
      } else {
        Text(coordinator.name)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
      QueueStatusIcon(status: coordinator.aggregateStatus)
    }
    .accessibilityIdentifier("sidebar.queueRow.\(coordinator.id)")
    .onChange(of: isRenaming) { _, editing in
      if editing {
        draftName = coordinator.name
        fieldFocused = true
      }
    }
    .onChange(of: fieldFocused) { _, focused in
      if !focused && isRenaming { commit() }
    }
  }

  private var isRenaming: Bool { env.ui.renamingQueueID == coordinator.id }

  private func commit() {
    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { env.workspace.renameQueue(coordinator.id, to: trimmed) }
    env.ui.renamingQueueID = nil
  }

  private func cancel() { env.ui.renamingQueueID = nil }
}

#if DEBUG
  /**
   Builds an in-memory environment whose queues sit in a spread of aggregate
   states, so the sidebar previews render its indicators without a live run.
   */
  @MainActor
  private enum SidebarPreview {
    static func environment() -> AppEnvironment {
      let env = PreviewSupport.environment(fullCodecSet: true)
      // The seeded "Queue 1" stays idle; add queues fixed into settled states.
      let movies = env.workspace.newQueue(name: "Movies")
      movies.hydrate(
        QueueSnapshot(
          id: movies.id,
          name: "Movies",
          items: [
            QueueItemSnapshot(
              sourcePath: "/Movies/A.mkv",
              outputPath: "/Movies/A (slimmed).mkv",
              status: .done
            ),
            QueueItemSnapshot(
              sourcePath: "/Movies/B.mkv",
              outputPath: "/Movies/B (slimmed).mkv",
              status: .done
            )
          ]
        )
      )
      let shows = env.workspace.newQueue(name: "Shows")
      shows.hydrate(
        QueueSnapshot(
          id: shows.id,
          name: "Shows",
          items: [
            QueueItemSnapshot(
              sourcePath: "/Shows/C.mkv",
              outputPath: "/Shows/C (slimmed).mkv",
              status: .missing
            )
          ]
        )
      )
      env.workspace.newQueue(name: "Archive")  // idle, empty
      env.workspace.selectQueue(movies.id)
      return env
    }
  }

  // The assembled `QueueSidebarView` (a selection-driven, sectioned sidebar
  // `List`) trips a SwiftUI `NSOutlineView`/`ViewListTree` assertion when rendered
  // in the app-hosted preview canvas — a preview-harness limitation, not an app
  // bug (the sidebar is the shipping UI and runs fine). Its pieces are covered
  // below via the row and status-icon previews instead of the whole list.
  #Preview("Sidebar Row") {
    let env = SidebarPreview.environment()
    let coordinators = env.workspace.coordinators
    // The second row is put into inline-rename mode so its TextField branch renders.
    env.ui.renamingQueueID = coordinators[1].id
    return List {
      QueueSidebarRow(coordinator: coordinators[0])
      QueueSidebarRow(coordinator: coordinators[1])
    }
    .environment(env)
    .frame(width: 240, height: 160)
  }
#endif
