import SwiftUI

/**
 The selected file's tracks as the run will write them: every track in output
 order, with the ones being dropped still listed but dimmed. Where the Override
 tab describes one track at a time and can change it, this reads the whole plan
 at once and changes nothing.
 */
struct OutputPreviewInspector: View {
  var body: some View {
    SelectedFileGate(identifierPrefix: "preview") { item, container in
      FileOutputPreview(item: item, container: container)
    }
  }
}

/// One file's plan: what it comes to, and the tracks it comes to it by.
private struct FileOutputPreview: View {
  @Environment(AppEnvironment.self)
  private var env
  let item: QueueItem
  let container: Container

  var body: some View {
    let tracks = outputTracks
    InspectorPane(helpAnchor: .trackPreview, helpAccessibilityIdentifier: "preview.help") {
      VStack(alignment: .leading, spacing: 4) {
        OutputPreviewSummary(tracks: tracks)

        // A re-scan keeps the tracks it is about to replace on screen, so say so
        // rather than let them read as current.
        if item.status == .probing {
          InspectorCaption("Re-scanning this file…")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } content: {
      OutputTrackTable(tracks: tracks)
    }
  }

  /**
   What the run will do to this file: its own override when it has one, and the
   queue's preset when it doesn't.
   */
  private var outputTracks: [OutputTrack] {
    TrackPlan(container: container, selection: item.selection, rules: env.rules.rules).outputTracks
  }
}

/// How much of the file survives the plan, as one line above the table.
private struct OutputPreviewSummary: View {
  let tracks: [OutputTrack]

  var body: some View {
    Text("Keeping \(keptCount) of \(tracks.count) tracks", bundle: #bundle)
      .font(.subheadline)
      .monospacedDigit()
      .accessibilityIdentifier("preview.summary")
  }

  private var keptCount: Int { tracks.count { $0.number != nil } }
}

/**
 The plan as a table: one row per track, in the order the output carries them,
 dimmed where the run drops them.

 A `Table` rather than a hand-laid stack because this is the pane's whole body
 and has a definite height to scroll within — the constraint that rules `Table`
 out inside scrolling content doesn't apply here.
 */
private struct OutputTrackTable: View {
  let tracks: [OutputTrack]

  var body: some View {
    // Only Role is left free to take the slack. The pane is 260pt at its
    // narrowest, and a column with no ceiling claims the width the columns to
    // its right need — which pushed Role off the edge entirely.
    Table(tracks) {
      TableColumn(LocalizedStringResource("Track", bundle: #bundle)) { TrackNumberCell(track: $0) }
        .width(38)
      TableColumn(LocalizedStringResource("Language", bundle: #bundle)) {
        PreviewCell(track: $0, identifier: "preview.language", text: $0.track.languageName)
      }
      .width(min: 56, ideal: 74, max: 110)
      TableColumn(LocalizedStringResource("Codec", bundle: #bundle)) {
        PreviewCell(track: $0, identifier: "preview.codec", text: $0.track.outputCodecSummary)
      }
      .width(min: 58, ideal: 82, max: 124)
      TableColumn(LocalizedStringResource("Role", bundle: #bundle)) {
        PreviewCell(track: $0, identifier: "preview.role", text: $0.dispositions.displayList)
      }
      .width(min: 60)
    }
    .accessibilityIdentifier("preview.table")
  }
}

/**
 Where the track lands in the output, and what kind it is. A dropped track has
 no position, so it takes an em dash rather than a number it will never have.
 */
private struct TrackNumberCell: View {
  let track: OutputTrack

  var body: some View {
    HStack(spacing: 3) {
      Text(track.number?.formatted(.number) ?? "—")
        .previewRowStyle(track)
        .monospacedDigit()
        .accessibilityIdentifier("preview.number.\(track.id)")
      Image(systemName: track.track.typeSymbolName)
        .previewRowStyle(track)
        .imageScale(.small)
        .accessibilityLabel(track.track.typeName)
    }
  }
}

/// One plain-text cell, dimmed with its row when the run drops the track.
private struct PreviewCell: View {
  let track: OutputTrack
  let identifier: String
  let text: String

  var body: some View {
    Text(text)
      .previewRowStyle(track)
      .accessibilityIdentifier("\(identifier).\(track.id)")
  }
}

extension View {

  /**
   How a row reads: dimmed when the run drops the track, and never wrapped —
   the pane is too narrow to spend two lines on one field, so what doesn't fit
   goes to the tooltip, which carries every fact the columns can't.

   Concrete colors rather than the `.primary`/`.secondary` hierarchy: inside an
   inspector SwiftUI resolves the hierarchy's second level to the primary label
   color, so a dropped row would read exactly like a kept one.
   */
  fileprivate func previewRowStyle(_ track: OutputTrack) -> some View {
    lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(track.track.isIncluded ? Color.primary : Color.secondary)
      .help(track.track.factsSummary)
  }
}

#if DEBUG
  /**
   A film with more tracks than the pane can show at once, and enough roles to
   read the Role column by: a commentary, a descriptive track, a stereo downmix,
   forced subtitles, and a language the rules drop entirely.
   */
  @MainActor
  private func previewContainer() -> Container {
    PreviewSupport.container(
      audio: [
        PreviewSupport.AudioTrack(codec: "truehd", language: "eng", channels: 8),
        PreviewSupport.AudioTrack(
          codec: "ac3",
          language: "eng",
          channels: 2,
          title: "Commentary with the director and the cinematographer",
          roles: [.comment]
        ),
        PreviewSupport.AudioTrack(
          codec: "eac3",
          language: "eng",
          channels: 2,
          title: "Descriptive audio",
          roles: [.visualImpaired]
        ),
        PreviewSupport.AudioTrack(codec: "dts", language: "jpn", channels: 6, roles: [.dub]),
        PreviewSupport.AudioTrack(codec: "aac", language: "fra", channels: 2)
      ],
      subtitles: [
        PreviewSupport.SubtitleTrack(codec: "subrip", language: "eng", roles: [.forced]),
        PreviewSupport.SubtitleTrack(
          codec: "subrip",
          language: "eng",
          title: "English (SDH)",
          roles: [.hearingImpaired]
        ),
        PreviewSupport.SubtitleTrack(codec: "hdmv_pgs_subtitle", language: "jpn")
      ]
    )
  }

  @MainActor
  private func previewEnvironment(overridden: Bool = false) -> AppEnvironment {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(
        name: "Film.mkv",
        status: .ready,
        container: previewContainer()
      )
    ])
    env.ui.inspectorMode = .preview
    env.capabilities.setForPreview(.loaded(.previewSample))
    env.queue.selection = [env.queue.items[0].id]
    let item = env.queue.items[0]
    if overridden, let container = item.container {
      item.selection = FileTrackSelection.seed(container: container, operations: [])
    }
    return env
  }

  #Preview("Preview — no selection") {
    OutputPreviewInspector()
      .environment(PreviewSupport.environment())
      .frame(width: 300, height: 560)
  }

  #Preview("Preview — rules plan") {
    OutputPreviewInspector()
      .environment(previewEnvironment())
      .frame(width: 300, height: 560)
  }

  // Every track dropped, which is the widest the dimmed styling ever reads.
  #Preview("Preview — everything dropped") {
    OutputPreviewInspector()
      .environment(previewEnvironment(overridden: true))
      .frame(width: 300, height: 560)
  }

  #Preview("Preview — widest pane") {
    OutputPreviewInspector()
      .environment(previewEnvironment())
      .frame(width: 420, height: 560)
  }
#endif
