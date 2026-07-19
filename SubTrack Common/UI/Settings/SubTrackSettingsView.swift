import SwiftUI

/**
 App preferences (⌘,): the General, Presets, Encoding, FFmpeg, and CLI tabs,
 plus Updates in the downloadable build, which is the only one that updates
 itself.
 */
struct SubTrackSettingsView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    TabView {
      GeneralSettingsTab()
        .tabItem { Label("General", systemImage: "gearshape") }
      PresetsSettingsTab()
        .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
      EncodingSettingsTab()
        .tabItem { Label("Encoding", systemImage: "cpu") }
      FFmpegSettingsTab()
        .tabItem { Label("FFmpeg", image: .ffmpegMark) }
      CLISettingsTab()
        .tabItem { Label("CLI", systemImage: "apple.terminal") }
      if let updates = env.updates {
        UpdatesSettingsTab(updates: updates)
          .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
      }
    }
    // Sized for the Presets tab's list-and-editor split; the others are content
    // that happily fills whatever it is given.
    .frame(width: 620, height: 420)
  }
}

#if DEBUG
  /**
   An in-memory environment for the Settings previews, letting them exercise the
   App Store (gated) and download (full) presentations.
   */
  @MainActor
  func settingsPreviewEnvironment(isAppStoreBuild: Bool) -> AppEnvironment {
    let env = PreviewSupport.environment(
      fullCodecSet: !isAppStoreBuild,
      isAppStoreBuild: isAppStoreBuild,
      // Only the downloadable build updates itself, so only it shows the tab.
      updates: isAppStoreBuild ? nil : StubUpdateChecker()
    )
    // Previews have no runnable ffmpeg, so seed the shared store with a fixture
    // (the LGPL build for the App Store gating, the full build otherwise).
    env.capabilities.setForPreview(.loaded(isAppStoreBuild ? .previewLGPLSample : .previewSample))
    return env
  }

  #Preview("Settings — Download") {
    SubTrackSettingsView()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
  }

  #Preview("Settings — App Store") {
    SubTrackSettingsView()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: true))
  }
#endif
