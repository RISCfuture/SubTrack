import SwiftUI

/**
 An Xcode-Build-Settings-style value menu for a single transcode-target codec:
 the build-aware catalog entries, the current value when it's a custom one, and
 an `Other…` item that reveals a raw text field. A warning triangle appears
 when the chosen codec isn't an encoder the resolved build supports.
 */
struct TranscodeTargetMenu: View {
  let title: LocalizedStringKey
  @Binding var codec: String
  let targets: [ConversionTarget]
  /// Whether the resolved build can encode a codec; `false` shows the warning.
  let isSupported: (String) -> Bool

  @State private var showingCustom = false

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        TranscodeTargetMenuContent(
          targets: targets,
          codec: $codec,
          chooseOther: { showingCustom = true }
        )
        if !codec.isEmpty, !isSupported(codec) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help("The current FFmpeg may not be able to encode this codec.")
            .accessibilityLabel(Text("Codec may not be supported", bundle: #bundle))
        }
      }
      .popover(isPresented: $showingCustom) {
        CustomCodecPopover(
          initialCodec: codec,
          commit: {
            codec = $0
            showingCustom = false
          },
          cancel: { showingCustom = false }
        )
      }
    }
  }
}

/**
 The value menu: the catalog entries, the current value when it's a custom
 one, and the `Other…` item that asks for a raw codec name.
 */
private struct TranscodeTargetMenuContent: View {
  let targets: [ConversionTarget]
  @Binding var codec: String
  /// Called by the `Other…` item to reveal the raw text field.
  let chooseOther: () -> Void

  var body: some View {
    Menu(menuLabel) {
      ForEach(targets) { target in
        Button {
          codec = target.codec
        } label: {
          if target.codec == codec {
            Label(target.menuTitle, systemImage: "checkmark")
          } else {
            Text(target.menuTitle)
          }
        }
      }
      if isCustomValue {
        Divider()
        Label(codec, systemImage: "checkmark")
      }
      Divider()
      Button(LocalizedStringResource("Other…", bundle: #bundle), action: chooseOther)
    }
    .fixedSize()
  }

  private var menuLabel: String {
    if let target = targets.first(where: { $0.codec == codec }) { return target.displayName }
    return codec.isEmpty ? String(localized: "None", bundle: #bundle) : codec
  }

  /// Whether the current value is a custom codec not present in the catalog.
  private var isCustomValue: Bool {
    !codec.isEmpty && !targets.contains { $0.codec == codec }
  }
}

/**
 The `Other…` popover's contents: a raw codec name seeded with the current
 value, committed trimmed or abandoned.
 */
private struct CustomCodecPopover: View {
  private static let codecFieldWidth = 200.0

  /// Called with the trimmed codec name when the user confirms.
  let commit: (String) -> Void
  let cancel: () -> Void

  @State private var draft: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Custom codec", bundle: #bundle).font(.subheadline)
      TextField("codec", text: $draft)
        .textFieldStyle(.roundedBorder)
        .frame(width: Self.codecFieldWidth)
      HStack {
        Spacer()
        Button(LocalizedStringResource("Cancel", bundle: #bundle), action: cancel)
        Button(LocalizedStringResource("Set", bundle: #bundle)) {
          commit(draft.trimmingCharacters(in: .whitespaces))
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
  }

  init(initialCodec: String, commit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
    _draft = State(initialValue: initialCodec)
    self.commit = commit
    self.cancel = cancel
  }
}

#if DEBUG
  #Preview("Transcode Target Menu") {
    @Previewable @State var supported = "hevc_videotoolbox"
    @Previewable @State var custom = "hevc"
    let targets = FileTrackSelection.availableTargets(for: .video, capabilities: .videoToolboxOnly)
    Form {
      TranscodeTargetMenu(
        title: "Video",
        codec: $supported,
        targets: targets,
        isSupported: { EncoderCapabilities.videoToolboxOnly.supportsVideo($0) }
      )
      TranscodeTargetMenu(
        title: "Video (custom, unsupported)",
        codec: $custom,
        targets: targets,
        isSupported: { EncoderCapabilities.videoToolboxOnly.supportsVideo($0) }
      )
    }
    .formStyle(.grouped)
    .frame(width: 320)
  }
#endif
