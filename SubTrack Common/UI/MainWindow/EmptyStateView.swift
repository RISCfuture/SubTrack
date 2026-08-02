import SwiftUI

/// The "drop videos here" empty state.
struct EmptyStateView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    ContentUnavailableView {
      Label(LocalizedStringResource("Drop Videos Here", bundle: #bundle), systemImage: "film.stack")
    } description: {
      Text("Drag video files or folders, or add them from the toolbar.", bundle: #bundle)
    } actions: {
      Button(LocalizedStringResource("Add Files…", bundle: #bundle)) {
        env.queue.ingest(FilePanels.chooseMovies())
      }
      .accessibilityIdentifier("queue.emptyState.add")
      // A question mark asks the user to already suspect what they're missing.
      // On a first launch the whole window is the question, so the offer is a
      // sentence — and one that names the answer rather than the affordance.
      Button(LocalizedStringResource("How SubTrack Works", bundle: #bundle)) {
        HelpAnchor.gettingStarted.open()
      }
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
