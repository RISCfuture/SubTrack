import SwiftUI

/// The "drop videos here" empty state.
struct EmptyStateView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    ContentUnavailableView {
      Label("Drop Videos Here", systemImage: "film.stack")
    } description: {
      Text("Drag video files or folders, or add them from the toolbar.")
    } actions: {
      Button("Add Files…") { env.queue.ingest(FilePanels.chooseMovies()) }
        .accessibilityIdentifier("queue.emptyState.add")
      // A question mark asks the user to already suspect what they're missing.
      // On a first launch the whole window is the question, so the offer is a
      // sentence — and one that names the answer rather than the affordance.
      Button("How SubTrack Works") { HelpAnchor.gettingStarted.open() }
        .buttonStyle(.link)
        .accessibilityIdentifier("queue.emptyState.help")
    }
    .accessibilityIdentifier("queue.emptyState")
  }
}

#if DEBUG
  #Preview("Empty state") {
    EmptyStateView()
      .environment(PreviewSupport.environment())
      .frame(width: 520, height: 380)
  }
#endif
