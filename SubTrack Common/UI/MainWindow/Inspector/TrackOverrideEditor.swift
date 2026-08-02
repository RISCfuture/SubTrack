import SwiftUI

/**
 What the run should do with one track: whether to include it at all and, when
 it is included, whether to convert it rather than copy it across untouched.
 */
struct TrackOverrideEditor: View {
  let targets: [ConversionTarget]
  @Binding var action: TrackAction

  var body: some View {
    Toggle(LocalizedStringResource("Include in output", bundle: #bundle), isOn: isIncluded)
      .inspectorCheckbox()
      .accessibilityIdentifier("override.include")

    if action != .drop {
      Picker(LocalizedStringResource("Convert to…", bundle: #bundle), selection: target) {
        Text("Keep original", bundle: #bundle).tag(String?.none)
        ForEach(targets) { target in
          Text(target.menuTitle).tag(String?.some(target.codec))
        }
      }
      .accessibilityIdentifier("override.convert")
    }
  }

  private var isIncluded: Binding<Bool> {
    Binding(
      get: { action != .drop },
      set: { include in action = include ? .copy : .drop }
    )
  }

  /**
   The codec the track is converted to, or `nil` for a stream-copied ("Keep
   original") track.
   */
  private var target: Binding<String?> {
    Binding(
      get: { if case let .convert(codec, _) = action { codec } else { nil } },
      set: { codec in action = codec.map { .convert(codec: $0, options: []) } ?? .copy }
    )
  }
}

#if DEBUG
  #Preview("Track Override — copied") {
    @Previewable @State var action: TrackAction = .copy
    Form {
      Section("Override") {
        TrackOverrideEditor(
          targets: FileTrackSelection.availableTargets(for: .video, capabilities: .full),
          action: $action
        )
      }
    }
    .formStyle(.grouped)
    .controlSize(.small)
    .frame(width: 300)
  }

  #Preview("Track Override — converted") {
    @Previewable @State var action: TrackAction = .convert(codec: "libx265", options: [])
    Form {
      Section("Override") {
        TrackOverrideEditor(
          targets: FileTrackSelection.availableTargets(for: .video, capabilities: .full),
          action: $action
        )
      }
    }
    .formStyle(.grouped)
    .controlSize(.small)
    .frame(width: 300)
  }

  #Preview("Track Override — skipped") {
    @Previewable @State var action: TrackAction = .drop
    Form {
      Section("Override") {
        TrackOverrideEditor(
          targets: FileTrackSelection.availableTargets(for: .audio, capabilities: .full),
          action: $action
        )
      }
    }
    .formStyle(.grouped)
    .controlSize(.small)
    .frame(width: 300)
  }
#endif
