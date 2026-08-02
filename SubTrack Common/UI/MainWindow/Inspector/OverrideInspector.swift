import SwiftUI

/**
 The selected file's own overrides: the name its output takes, and what the
 run does with each of its tracks. Everything here departs from the queue's
 preset for this one file.
 */
struct OverrideInspector: View {
  var body: some View {
    SelectedFileGate(identifierPrefix: "override") { item, container in
      FileOverrideEditor(item: item, container: container)
    }
  }
}

/**
 One file's overrides: the name its output takes, the track the tab is
 describing, and that track's detail and controls.
 */
private struct FileOverrideEditor: View {
  @Environment(AppEnvironment.self)
  private var env
  let item: QueueItem
  let container: Container

  /**
   The track the tab is describing, or `nil` before one has been picked — in
   which case it falls back to the first track in output order, so the pane is
   never blank and switching files never leaves a track missing.
   */
  @State private var pickedTrack: UInt?

  var body: some View {
    InspectorForm(helpAnchor: .trackOverrides, helpAccessibilityIdentifier: "override.help") {
      VStack(alignment: .leading, spacing: 4) {
        Picker(LocalizedStringResource("Track", bundle: #bundle), selection: trackSelection) {
          ForEach(plan.tracks) { track in
            Text(track.pickerTitle)
              // Concrete colors, not the `.primary`/`.secondary` hierarchy: inside an
              // inspector SwiftUI resolves the hierarchy's second level to the primary
              // label color, so a skipped row would read exactly like a kept one.
              .foregroundStyle(track.isIncluded ? Color.primary : Color.secondary)
              .tag(UInt?.some(track.id))
          }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("override.trackPicker")

        // A re-scan keeps the tracks it is about to replace on screen, so say so
        // rather than let them read as current.
        if item.status == .probing {
          InspectorCaption("Re-scanning this file…")
        }
      }
    } content: {
      Section("File name") {
        OutputNameOverrideEditor(item: item)
      }

      if let track = selectedTrack {
        Section("Track") {
          TrackFactsView(facts: track.facts)
        }

        Section("Override") {
          if let unsupportedCodec {
            UnsupportedCodecWarning(codec: unsupportedCodec)
          }

          TrackOverrideEditor(
            targets: env.transcodeTargets(for: track.type),
            action: action(for: track)
          )

          if item.selection != nil {
            Button(LocalizedStringResource("Reset to Rules", bundle: #bundle)) {
              item.selection = nil
            }
            .accessibilityIdentifier("override.reset")
          }
        }
      }
    }
    .onChange(of: item.selection) { env.queue.revalidateCompatibility(item) }
  }

  /**
   What the run will do to this file: its own override when it has one, and the
   queue's preset when it doesn't.
   */
  private var plan: TrackPlan {
    TrackPlan(container: container, selection: item.selection, rules: env.rules.rules)
  }

  private var selectedTrack: PlannedTrack? {
    plan.tracks.first { $0.id == pickedTrack } ?? plan.tracks.first
  }

  /**
   The first target codec the selected `ffmpeg` build can't encode across this
   file's plan, or `nil` when every target is supported.
   */
  private var unsupportedCodec: String? {
    env.queue.encoderCapabilities.firstUnsupported(in: plan.selection.operations())?.1
  }

  private var trackSelection: Binding<UInt?> {
    Binding(
      get: { selectedTrack?.id },
      set: { pickedTrack = $0 }
    )
  }

  /**
   Editing one track's action promotes the whole plan to this file's own
   override, so the first edit captures the rules' outcome for every other
   track rather than leaving them to drift with the rules.
   */
  private func action(for track: PlannedTrack) -> Binding<TrackAction> {
    Binding(
      get: { track.action },
      set: { item.selection = plan.setting($0, forTrack: track.id, type: track.type) }
    )
  }
}

/**
 Names the target codec the resolved build can't encode, and the two ways out of
 it, so a plan that would fail says so before the run does.
 */
private struct UnsupportedCodecWarning: View {
  let codec: String

  var body: some View {
    // The fix is a paragraph, not a clause — which build to switch to depends
    // on which one is resolved — so the message states the problem and the
    // page beneath it states the remedy.
    VStack(alignment: .leading, spacing: 2) {
      Label(
        "The current FFmpeg can’t encode “\(codec)”.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.orange)
      .font(.caption)
      HelpTopicButton(anchor: .unsupportedCodec, accessibilityIdentifier: "override.codecHelp")
    }
  }
}

#if DEBUG
  /**
   An environment whose single selected queue item carries a probed container,
   so the Override tab resolves a file and describes its tracks.
   */
  @MainActor
  private func overrideEnvironment(customName: String? = nil) -> AppEnvironment {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(
        name: "Film.mkv",
        status: .ready,
        container: PreviewSupport.container()
      )
    ])
    env.ui.inspectorMode = .override
    env.capabilities.setForPreview(.loaded(.previewSample))
    env.queue.selection = [env.queue.items[0].id]
    if let customName { env.queue.setCustomName(customName, for: env.queue.items[0]) }
    return env
  }

  /**
   An environment whose single selected item is in `status` with nothing probed
   yet, for the states the tab shows before it has tracks to describe.
   */
  @MainActor
  private func uninspectedEnvironment(status: QueueItemState) -> AppEnvironment {
    let env = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(name: "Film.mkv", status: status)
    ])
    env.ui.inspectorMode = .override
    env.queue.selection = [env.queue.items[0].id]
    return env
  }

  #Preview("Override — no selection") {
    OverrideInspector()
      .environment(PreviewSupport.environment())
      .frame(width: 300, height: 560)
  }

  #Preview("Override — probing") {
    OverrideInspector()
      .environment(uninspectedEnvironment(status: .probing))
      .frame(width: 300, height: 560)
  }

  #Preview("Override — missing source") {
    OverrideInspector()
      .environment(uninspectedEnvironment(status: .missing))
      .frame(width: 300, height: 560)
  }

  #Preview("Override — probe failed") {
    OverrideInspector()
      .environment(uninspectedEnvironment(status: .failed("ffprobe exited with code 1")))
      .frame(width: 300, height: 560)
  }

  #Preview("Override — re-scanning") {
    let env = overrideEnvironment()
    env.queue.items[0].status = .probing
    return OverrideInspector()
      .environment(env)
      .frame(width: 300, height: 560)
  }

  #Preview("Override — default name") {
    OverrideInspector()
      .environment(overrideEnvironment())
      .frame(width: 300, height: 560)
  }

  #Preview("Override — custom name") {
    OverrideInspector()
      .environment(overrideEnvironment(customName: "Film (director’s cut)"))
      .frame(width: 300, height: 560)
  }

  #Preview("Override — edited tracks") {
    let env = overrideEnvironment()
    let item = env.queue.items[0]
    item.selection = FileTrackSelection.seed(container: item.container!, operations: [])
    return OverrideInspector()
      .environment(env)
      .frame(width: 300, height: 560)
  }
#endif
