import SwiftUI

/**
 Manages the saved presets: the list of them on the left, and the selected
 one's editable rules on the right.
 */
struct PresetsSettingsTab: View {
  /// Wide enough for a typical preset name, leaving the rest to the editor.
  private static let listWidth: CGFloat = 170

  @Environment(AppEnvironment.self)
  private var env
  @State private var selection: UUID?

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        PresetList(selection: $selection)
        if let reason = env.syncMonitor?.unavailableReason {
          Divider()
          PresetSyncNotice(reason: reason)
        }
      }
      .frame(width: Self.listWidth)
      Divider()
      if let preset = selectedPreset {
        PresetEditor(preset: preset) { selection = nil }
      } else {
        ContentUnavailableView(
          "No Preset Selected",
          systemImage: "slider.horizontal.3",
          description: Text("Select a preset to edit its rules.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear { selection = selection ?? env.presets.presets.first?.id }
    // The presets can arrive from CloudKit while the tab is already open, and
    // land in a list that had nothing to select when it appeared.
    .onChange(of: env.presets.presets.isEmpty) { _, isEmpty in
      if !isEmpty { selection = selection ?? env.presets.presets.first?.id }
    }
    .settingsHelp(.presets, accessibilityIdentifier: "settings.presetsHelp")
  }

  private var selectedPreset: Preset? {
    env.presets.presets.first { $0.id == selection }
  }
}

/**
 The presets to choose between. Selection only — a preset is renamed and
 deleted through the editor beside it, where there is room to say which preset
 the change is about.
 */
private struct PresetList: View {
  @Environment(AppEnvironment.self)
  private var env
  @Binding var selection: UUID?

  var body: some View {
    List(env.presets.presets, selection: $selection) { preset in
      Text(preset.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .tag(preset.id)
    }
    .accessibilityIdentifier("settings.presetList")
  }
}

/**
 Why presets are not syncing, shown beneath the preset list only while
 something is wrong. A user whose presets sync sees nothing at all — success
 needs no chrome.
 */
private struct PresetSyncNotice: View {
  let reason: SyncUnavailableReason

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(reason.userMessage)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("settings.presetSyncNotice")
      HelpTopicButton(anchor: .presetSync, accessibilityIdentifier: "settings.presetSyncHelp")
    }
    .font(.caption)
    .foregroundStyle(Color.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }
}

#if DEBUG
  #Preview("Presets Tab") {
    PresetsSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
      .frame(width: 620, height: 420)
  }

  #Preview("Presets Tab — no presets") {
    let env = settingsPreviewEnvironment(isAppStoreBuild: false)
    for preset in env.presets.presets { env.presets.delete(preset) }
    return PresetsSettingsTab()
      .environment(env)
      .frame(width: 620, height: 420)
  }

  #Preview("Preset sync unavailable") {
    PresetSyncNotice(reason: .noAccount)
      .frame(width: 170)
  }
#endif
