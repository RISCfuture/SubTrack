import SwiftUI

/**
 The workspace source list: one row per queue with its name and an aggregate
 status indicator, a New Queue affordance, and per-row rename/delete. Selection
 and every structural edit drive the ``Workspace``, so the detail view and
 inspector follow the selected queue.
 */
struct QueueSidebarView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    List(selection: selection) {
      Section("Queues") {
        ForEach(env.workspace.coordinators) { coordinator in
          QueueSidebarRow(coordinator: coordinator)
            .tag(coordinator.id)
            .contextMenu { QueueSidebarRowMenu(coordinator: coordinator) }
        }
      }
    }
    .accessibilityIdentifier("sidebar.queueList")
    .safeAreaInset(edge: .bottom) { NewQueueBar() }
    .confirmationDialog(
      deletionTitle,
      isPresented: deletionPresented,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { coordinator in
      Button(LocalizedStringResource("Delete Queue", bundle: #bundle), role: .destructive) {
        env.workspace.deleteQueue(coordinator.id)
      }
      Button(LocalizedStringResource("Cancel", bundle: #bundle), role: .cancel) {}
    } message: { _ in
      Text("This queue has unfinished work that will be cancelled.", bundle: #bundle)
    }
  }

  /**
   Reads the effective selection (never `nil`, since the workspace always holds
   a queue) and writes it back through the workspace.
   */
  private var selection: Binding<UUID?> {
    Binding(
      get: { env.workspace.selectedCoordinator.id },
      set: { if let id = $0 { env.workspace.selectQueue(id) } }
    )
  }

  private var pendingDeletion: QueueCoordinator? {
    guard let id = env.ui.queuePendingDeletion else { return nil }
    return env.workspace.coordinators.first { $0.id == id }
  }

  private var deletionPresented: Binding<Bool> {
    Binding(
      get: { env.ui.queuePendingDeletion != nil },
      set: { if !$0 { env.ui.queuePendingDeletion = nil } }
    )
  }

  private var deletionTitle: String {
    String(localized: "Delete “\(pendingDeletion?.name ?? "")”?", bundle: #bundle)
  }

  /// Creates the queue sidebar view.
  init() {}
}

/// Right-click actions for a queue row.
private struct QueueSidebarRowMenu: View {
  @Environment(AppEnvironment.self)
  private var env
  let coordinator: QueueCoordinator

  var body: some View {
    Button(LocalizedStringResource("Rename", bundle: #bundle)) {
      beginQueueRename(coordinator, in: env)
    }
    Button(LocalizedStringResource("Delete", bundle: #bundle), role: .destructive) {
      requestQueueDeletion(coordinator, in: env)
    }
  }
}

/// The bottom bar's New Queue button.
private struct NewQueueBar: View {
  private static let horizontalInset: Double = 10
  private static let verticalInset: Double = 6

  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      HStack(spacing: 0) {
        Button {
          env.workspace.newQueue(name: env.workspace.nextQueueName())
        } label: {
          Label(LocalizedStringResource("New Queue", bundle: #bundle), systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .padding(.horizontal, Self.horizontalInset)
        .padding(.vertical, Self.verticalInset)
        .accessibilityIdentifier("sidebar.newQueue")
        Spacer(minLength: 0)
      }
    }
    .background(.bar)
  }
}

/**
 Puts a queue's sidebar row into inline-rename mode. Shared by the context menu
 and the Rename Queue command.
 */
@MainActor
func beginQueueRename(_ coordinator: QueueCoordinator, in env: AppEnvironment) {
  env.ui.renamingQueueID = coordinator.id
}

/**
 Deletes a queue, first confirming when it has unfinished work. Shared by the
 context menu and the Delete Queue command.
 */
@MainActor
func requestQueueDeletion(_ coordinator: QueueCoordinator, in env: AppEnvironment) {
  if coordinator.hasUnfinishedWork {
    env.ui.queuePendingDeletion = coordinator.id
  } else {
    env.workspace.deleteQueue(coordinator.id)
  }
}

#if DEBUG
  // The assembled `QueueSidebarView` gets no preview of its own: its
  // selection-driven, sectioned `List` trips a SwiftUI `NSOutlineView`/
  // `ViewListTree` assertion in the app-hosted preview canvas — a preview-harness
  // limitation, not an app bug (the sidebar is the shipping UI and runs fine). Its
  // pieces are covered by this preview and the ones in `QueueSidebarRow`.
  #Preview("New Queue Bar") {
    NewQueueBar()
      .environment(PreviewSupport.environment())
      .frame(width: 240)
  }
#endif
