import SwiftUI

/**
 One reason the queue can't safely name the files it would write. Shown against
 the queue's name format and against the name of any single file caught up in
 it.
 */
struct ConflictWarning: View {
  let conflict: OutputNameConflict
  let accessibilityIdentifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(conflict.message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .font(.caption)
        .accessibilityIdentifier(accessibilityIdentifier)
      ForEach(listedSources, id: \.self) { source in
        Text(source.path(percentEncoded: false))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
      }
      HelpTopicButton(anchor: .nameConflicts, accessibilityIdentifier: "conflict.help")
    }
  }

  /**
   The files to spell out under the message. A conflict between several files
   has to name them — the message can only say how many — but one that already
   names its single file would just repeat itself, in a head-truncated path
   that reads as a fragment of nothing.
   */
  private var listedSources: [URL] {
    conflict.sources.count > 1 ? conflict.sources : []
  }
}

#if DEBUG
  #Preview("Conflict — one file") {
    ConflictWarning(
      conflict: .overwritesSource(sources: [URL(filePath: "/Movies/Film.mkv")]),
      accessibilityIdentifier: "preview.conflict"
    )
    .padding()
    .frame(width: 300)
  }

  #Preview("Conflict — several files") {
    ConflictWarning(
      conflict: .duplicateOutputs(
        name: "Show (slimmed).mkv",
        sources: [
          URL(filePath: "/Volumes/Media/Television/Show/Season 1/Show.mkv"),
          URL(filePath: "/Volumes/Media/Television/Show/Season 2/Show.mkv"),
          URL(filePath: "/Volumes/Archive/Rips/Pending review/Show.mkv")
        ]
      ),
      accessibilityIdentifier: "preview.conflict"
    )
    .padding()
    .frame(width: 300)
  }
#endif
