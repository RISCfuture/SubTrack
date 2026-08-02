import SwiftUI

/**
 The tracks of the one selected file, or why there aren't any to show.

 Every tab that describes a file's tracks needs the same five answers, and
 `identifierPrefix` is what lets each of them be addressed on its own — the
 Override tab's "no file selected" and the Preview tab's are the same view but
 not the same element.
 */
struct SelectedFileGate<Content: View>: View {
  @Environment(AppEnvironment.self)
  private var env

  /// Namespaces the placeholder states, e.g. `"override"` or `"preview"`.
  let identifierPrefix: String

  @ViewBuilder let content: (QueueItem, Container) -> Content

  var body: some View {
    if let item = selectedItem {
      if let container = item.container {
        content(item, container)
      } else {
        UninspectedFileView(item: item, identifierPrefix: identifierPrefix)
      }
    } else {
      ContentUnavailableView(
        "No File Selected",
        systemImage: "circle.slash",
        description: Text("Select a single file to inspect it.", bundle: #bundle)
      )
      .accessibilityIdentifier("\(identifierPrefix).noFileSelected")
    }
  }

  /// The selection only when it is exactly one file — two files have no one plan.
  private var selectedItem: QueueItem? {
    guard env.queue.selection.count == 1, let id = env.queue.selection.first else { return nil }
    return env.queue.items.first { $0.id == id }
  }
}

/**
 Why the selected file has no tracks to describe yet. Each state names what
 the file is actually doing — a file waiting its turn behind a hundred others
 is not the same as no file being selected, and the tab must not read as
 though nothing is chosen.
 */
private struct UninspectedFileView: View {
  let item: QueueItem
  let identifierPrefix: String

  var body: some View {
    switch item.status {
      case .waiting, .probing:
        VStack {
          ProgressView().controlSize(.small)
          Text("Inspecting “\(item.displayName)”…", bundle: #bundle)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("\(identifierPrefix).inspecting")
      case .missing:
        ContentUnavailableView(
          "Source Missing",
          systemImage: "questionmark.folder",
          description: Text(
            "“\(item.displayName)” is no longer where it was added from.",
            bundle: #bundle
          )
        )
        .accessibilityIdentifier("\(identifierPrefix).sourceMissing")
      case .failed(let reason):
        ContentUnavailableView(
          "Couldn’t Inspect File",
          systemImage: "exclamationmark.triangle",
          description: Text(reason)
        )
        .accessibilityIdentifier("\(identifierPrefix).probeFailed")
      default:
        ContentUnavailableView(
          "Not Inspected",
          systemImage: "questionmark.square.dashed",
          description: Text("Re-scan “\(item.displayName)” to read its tracks.", bundle: #bundle)
        )
        .accessibilityIdentifier("\(identifierPrefix).notInspected")
    }
  }
}
