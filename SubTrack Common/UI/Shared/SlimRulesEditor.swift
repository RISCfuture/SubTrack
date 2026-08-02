import SwiftUI

/**
 The keep-rules form, over whichever rules it is handed: the selected queue's
 in the inspector, a stored preset's in Settings. Presents friendly pickers
 over the raw ffmpeg strings — a searchable language chooser, a probe-driven
 preferred-codec list editor per media type, and build-aware transcode-target
 menus — each still editable as raw text.

 Emits its own `Section`s, so a caller places it inside a `Form` rather than
 wrapping it in a section of their own.
 */
struct SlimRulesEditor: View {
  @Environment(AppEnvironment.self)
  private var env
  @Binding var rules: SlimRules

  var body: some View {
    Section("Track Selection") {
      CaptionedControl(
        "Kept in priority order; others are removed. The first language’s audio becomes the default track."
      ) {
        LanguagePickerButton(languages: $rules.languages)
      }
      CaptionedControl("Keep tracks that have no language metadata.") {
        Toggle(
          LocalizedStringResource("Keep untagged tracks", bundle: #bundle),
          isOn: $rules.preserveNoLanguages
        )
        .inspectorCheckbox()
        .accessibilityIdentifier("rules.keepUntagged")
      }
      CaptionedControl("Keep non-default audio such as commentary and downmixes.") {
        Toggle(
          LocalizedStringResource("Include commentary / extra audio", bundle: #bundle),
          isOn: $rules.includeOtherAudio
        )
        .inspectorCheckbox()
      }
    }

    Section {
      PreferredCodecEditor(
        title: "Video",
        accessibilityIdentifier: "rules.preferredVideo",
        codecs: $rules.videoPreferredCodecs,
        mediaCodecs: mediaCodecs(\.videoCodecs)
      )
      PreferredCodecEditor(
        title: "Audio",
        accessibilityIdentifier: "rules.preferredAudio",
        codecs: $rules.audioPreferredCodecs,
        mediaCodecs: mediaCodecs(\.audioCodecs)
      )
      PreferredCodecEditor(
        title: "Subtitle",
        accessibilityIdentifier: "rules.preferredSubtitle",
        codecs: $rules.subtitlePreferredCodecs,
        mediaCodecs: mediaCodecs(\.subtitleCodecs)
      )
    } header: {
      InspectorSectionHeader(
        title: "Preferred codecs",
        help:
          "Tracks already using one of these are kept as-is; anything else is transcoded to the target below."
      )
    }

    Section {
      TranscodeTargetMenu(
        title: "Video",
        codec: $rules.videoConversionCodec,
        targets: env.transcodeTargets(for: .video),
        isSupported: { env.queue.encoderCapabilities.supportsVideo($0) }
      )
      TranscodeTargetMenu(
        title: "Audio",
        codec: $rules.audioConversionCodec,
        targets: env.transcodeTargets(for: .audio),
        isSupported: { env.queue.encoderCapabilities.supportsAudio($0) }
      )
    } header: {
      InspectorSectionHeader(
        title: "Transcode targets",
        help: "The codec used when a track isn’t already one of the preferred codecs."
      )
    }
  }

  /**
   The resolved build's codecs for a media type, from the shared probe; empty
   until a build has been probed.
   */
  private func mediaCodecs(_ keyPath: KeyPath<FFmpegCapabilities, [FFmpegCodec]>) -> [FFmpegCodec] {
    guard case .loaded(let capabilities) = env.capabilities.state else { return [] }
    return capabilities[keyPath: keyPath]
  }
}

#if DEBUG
  /**
   An environment whose capability probe has already resolved, so the
   preferred-codec editors offer the probed build's codecs.
   */
  @MainActor
  private func probedPreviewEnvironment() -> AppEnvironment {
    let env = PreviewSupport.environment()
    env.capabilities.setForPreview(.loaded(.previewSample))
    return env
  }

  // Both hosts (the inspector and Settings' preset editor) place this inside a
  // `Form`, and the editor emits bare `Section`s, so the previews supply one.
  #Preview("Slim Rules — probed") {
    @Previewable @State var rules = SlimRules.default
    Form {
      SlimRulesEditor(rules: $rules)
    }
    .formStyle(.grouped)
    .environment(probedPreviewEnvironment())
    .frame(width: 340, height: 620)
  }

  // Nothing has probed a build yet: the preferred-codec editors have no codecs to
  // suggest, and the transcode menus fall back to the built-in catalog.
  #Preview("Slim Rules — no build probed") {
    @Previewable @State var rules = SlimRules.default
    Form {
      SlimRulesEditor(rules: $rules)
    }
    .formStyle(.grouped)
    .environment(PreviewSupport.environment())
    .frame(width: 340, height: 620)
  }
#endif
