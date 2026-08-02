import SwiftUI

/**
 One preferred-codec list editor (video, audio, or subtitle): a summary of the
 priority-ordered codecs and an **Edit…** button presenting a
 ``StringListEditor`` whose `+` menu offers the codecs the resolved `ffmpeg`
 build reports it can decode. Codecs the build can't decode are still shown
 (they simply never match an input track) but flagged with a warning.
 */
struct PreferredCodecEditor: View {
  let title: LocalizedStringKey

  /// Names which of the three media types this row edits, for UI tests.
  let accessibilityIdentifier: String
  @Binding var codecs: [String]
  /**
   The resolved build's codecs for this media type (from the shared probe);
   empty when no build has been probed yet.
   */
  let mediaCodecs: [FFmpegCodec]
  @State private var showingEditor = false

  var body: some View {
    LabeledContent(title) {
      EditableSummary(summary: summary, accessibilityIdentifier: accessibilityIdentifier) {
        showingEditor = true
      }
      .popover(isPresented: $showingEditor) {
        StringListEditor(
          values: $codecs,
          accessibilityIdentifier: accessibilityIdentifier,
          reorderable: true,
          placeholder: "codec",
          resolvedLabel: { name(for: $0) },
          isKnown: { isDecodable($0) },
          warningHelp: "This codec isn’t in the current FFmpeg build’s decodable list.",
          knownValues: addableCodecs.map {
            CodeChoice(
              title: String(localized: "\($0.name) — \($0.summary)", bundle: #bundle),
              code: $0.name
            )
          }
        )
      }
    }
  }

  private var summary: String {
    codecs.isEmpty ? String(localized: "None", bundle: #bundle) : codecs.joined(separator: ", ")
  }

  /// The decodable codecs from the probe (may be empty).
  private var decodable: [FFmpegCodec] {
    mediaCodecs.filter(\.canDecode)
  }

  /// Decodable codecs not already chosen, for the `+` menu.
  private var addableCodecs: [FFmpegCodec] {
    decodable.filter { !codecs.contains($0.name) }
  }

  private func name(for code: String) -> String? {
    decodable.first { $0.name == code }?.summary
  }

  /**
   A codec is "known" when a build has been probed and lists it as decodable.
   Without a probe there is nothing to check against, so nothing is flagged.
   */
  private func isDecodable(_ code: String) -> Bool {
    decodable.isEmpty || decodable.contains { $0.name == code }
  }
}

#if DEBUG
  #Preview("Preferred Codec Row") {
    @Previewable @State var codecs = ["hevc", "h264", "theora"]
    let media = [
      FFmpegCodec(
        name: "hevc",
        summary: "H.265 / HEVC",
        mediaType: .video,
        canEncode: true,
        canDecode: true
      ),
      FFmpegCodec(
        name: "h264",
        summary: "H.264 / AVC",
        mediaType: .video,
        canEncode: true,
        canDecode: true
      ),
      FFmpegCodec(
        name: "av1",
        summary: "AV1",
        mediaType: .video,
        canEncode: false,
        canDecode: true
      ),
      FFmpegCodec(
        name: "vp9",
        summary: "Google VP9",
        mediaType: .video,
        canEncode: false,
        canDecode: true
      )
    ]
    Form {
      PreferredCodecEditor(
        title: "Video",
        accessibilityIdentifier: "preview.preferredVideo",
        codecs: $codecs,
        mediaCodecs: media
      )
    }
    .formStyle(.grouped)
    .frame(width: 320)
  }
#endif
