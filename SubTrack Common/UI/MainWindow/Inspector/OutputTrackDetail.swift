import SwiftUI

/// A labelled group of facts, as the detail pane lists them under one heading.
struct TrackFactSection: Identifiable {
  let name: String
  let facts: [TrackFact]

  var id: String { name }
}

/**
 Everything known about the track the list has picked: what the run will do
 with it, what the file says it is, and every tag the probe read — the last of
 which is the part no fixed set of rows can anticipate, and the reason this is
 a scrolling form rather than a fixed block.
 */
struct OutputTrackDetail: View {
  let track: OutputTrack

  var body: some View {
    Form {
      ForEach(track.detailSections) { section in
        Section(section.name) {
          TrackFactsView(facts: section.facts)
        }
      }
    }
    .formStyle(.grouped)
    // A codec name or an encoder's argument list is something you copy into a
    // terminal, not something you retype.
    .textSelection(.enabled)
    .accessibilityIdentifier("preview.detail")
  }
}

extension OutputTrack {

  /**
   Everything known about the track, grouped as the detail pane lists it: what
   the run does, what the track is, and the container's own metadata verbatim.
   */
  var detailSections: [TrackFactSection] {
    [
      TrackFactSection(name: String(localized: "Output", bundle: #bundle), facts: outputFacts),
      TrackFactSection(name: String(localized: "Track", bundle: #bundle), facts: trackFacts),
      metadataSection
    ].compactMap(\.self)
  }

  /**
   What the run leaves in the output. Where the track lands and whether it is
   copied, converted, or dropped are the list's own columns, so repeating them
   here would only spend rows on what is already on screen.
   */
  private var outputFacts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Codec", bundle: #bundle),
        value: track.outputCodecSummary
      ),
      encoderOptions.map {
        TrackFact(name: String(localized: "Encoder options", bundle: #bundle), value: $0)
      },
      TrackFact(
        name: String(localized: "Flags", bundle: #bundle),
        value: Self.flagList(dispositions)
      )
    ].compactMap(\.self)
  }

  /**
   What the file says the track is. The same facts the Override tab lists,
   led by the stream's own index — which is what names it to `ffmpeg`, and the
   only way to tell two otherwise identical tracks apart.
   */
  private var trackFacts: [TrackFact] {
    [
      TrackFact(
        name: String(localized: "Source index", bundle: #bundle),
        value: track.stream.index.formatted(.number)
      )
    ] + track.facts
      + [
        track.stream.nbReadPackets.map {
          TrackFact(
            name: String(localized: "Packets", bundle: #bundle),
            value: $0.formatted(.number)
          )
        }
      ].compactMap(\.self)
  }

  /**
   The container's tags exactly as the probe reported them, `nil` when it
   reported none. Nothing is filtered: a release's own tags are the facts no
   list of named rows can predict, and the ones worth reading when a track
   isn't behaving as its language and codec suggest it should.
   */
  private var metadataSection: TrackFactSection? {
    let tags = track.stream.tags
    guard !tags.isEmpty else { return nil }
    return TrackFactSection(
      name: String(localized: "Metadata", bundle: #bundle),
      facts: tags.sorted { $0.key < $1.key }.map { TrackFact(name: $0.key, value: $0.value) }
    )
  }

  /// The arguments the transcode runs under, `nil` when the track isn't converted.
  private var encoderOptions: String? {
    guard case let .convert(_, options) = track.action, !options.isEmpty else { return nil }
    return options.joined(separator: " ")
  }

  private static func flagList(_ dispositions: Set<Disposition>) -> String {
    dispositions.isEmpty ? String(localized: "None", bundle: #bundle) : dispositions.displayList
  }
}

#if DEBUG
  /// The first track of `type` in the standard preview container, kept and numbered.
  @MainActor
  private func previewTrack(_ type: StreamOperation.StreamType) -> OutputTrack {
    let container = PreviewSupport.container(
      audio: [
        PreviewSupport.AudioTrack(
          codec: "ac3",
          language: "eng",
          channels: 6,
          title: "Director’s Commentary",
          roles: [.comment]
        )
      ],
      subtitles: [PreviewSupport.SubtitleTrack(codec: "subrip", language: "eng", roles: [.forced])]
    )
    let plan = TrackPlan(container: container, selection: nil, rules: .default)
    return plan.outputTracks.first { $0.track.type == type } ?? plan.outputTracks[0]
  }

  #Preview("Track detail — video") {
    OutputTrackDetail(track: previewTrack(.video))
      .frame(width: 300, height: 460)
  }

  #Preview("Track detail — audio") {
    OutputTrackDetail(track: previewTrack(.audio))
      .frame(width: 300, height: 460)
  }

  #Preview("Track detail — subtitle") {
    OutputTrackDetail(track: previewTrack(.subtitle))
      .frame(width: 300, height: 460)
  }
#endif
