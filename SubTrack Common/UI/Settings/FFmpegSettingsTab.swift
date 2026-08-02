import SwiftUI

/**
 Chooses where `ffmpeg`/`ffprobe` come from: the built-in binary or a
 user-selected folder, and reports the resolved build's version and formats.
 */
struct FFmpegSettingsTab: View {
  /// Separates the two sections more clearly than the spacing within either one.
  private static let sectionSpacing: CGFloat = 20

  var body: some View {
    VStack(alignment: .leading, spacing: Self.sectionSpacing) {
      FFmpegLocationSection()
      Divider()
      FFmpegInformationSection()
      Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .settingsHelp(.settingsFFmpeg, accessibilityIdentifier: "settings.ffmpegHelp")
  }
}

/**
 Where `ffmpeg`/`ffprobe` are resolved from — a fixed notice in the App Store
 build, and the built-in/custom choice everywhere else.
 */
private struct FFmpegLocationSection: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    @Bindable var settings = env.ffmpegSettings
    VStack(alignment: .leading, spacing: 8) {
      Text("FFmpeg Location", bundle: #bundle)
      if env.featureFlags.isAppStoreBuild {
        BuiltInOnlyNotice()
      } else {
        // Each option carries its own identifier: SwiftUI gives every radio
        // button the Picker's own identifier as well, so the Picker's can't
        // select one.
        Picker(
          LocalizedStringResource("FFmpeg Location", bundle: #bundle),
          selection: $settings.mode
        ) {
          Text("Built-in", bundle: #bundle)
            .tag(FFmpegLocationMode.builtIn)
            .accessibilityIdentifier("settings.ffmpegModeBuiltIn")
          Text("Custom…", bundle: #bundle)
            .tag(FFmpegLocationMode.custom)
            .accessibilityIdentifier("settings.ffmpegModeCustom")
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .accessibilityIdentifier("settings.ffmpegMode")

        if settings.mode == .custom { CustomFFmpegFolderPicker() }
      }
    }
    .onAppear {
      // The App Store build can't run a custom ffmpeg; ignore any stale preference.
      if env.featureFlags.isAppStoreBuild { env.ffmpegSettings.mode = .builtIn }
    }
  }
}

/**
 The App Store build's stand-in for the location picker: the built-in ffmpeg
 is the only one it can run.
 */
private struct BuiltInOnlyNotice: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Built-in", bundle: #bundle).foregroundStyle(.secondary)
        FullVersionHelpLink()
      }
      Text("Using a custom ffmpeg is available in the downloadable version.", bundle: #bundle)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }
}

/**
 The chosen custom folder, the two ways to change it, and whether that folder
 actually holds the two binaries.
 */
private struct CustomFFmpegFolderPicker: View {
  @Environment(AppEnvironment.self)
  private var env
  @State private var isDetecting = false
  @State private var detectionFoundNothing = false

  var body: some View {
    let settings = env.ffmpegSettings
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Text(
          settings.customDirectory.isEmpty
            ? String(localized: "Not chosen", bundle: #bundle)
            : settings.customDirectory
        )
        .foregroundStyle(settings.customDirectory.isEmpty ? .secondary : .primary)
        .lineLimit(1)
        .truncationMode(.middle)
        Spacer(minLength: 0)
        if isDetecting { ProgressView().controlSize(.small) }
        Button(LocalizedStringResource("Auto-detect", bundle: #bundle)) { detect() }
          .accessibilityIdentifier("settings.ffmpegAutoDetect")
        Button(LocalizedStringResource("Choose…", bundle: #bundle)) { chooseFolder() }
          .accessibilityIdentifier("settings.ffmpegChoose")
      }
      .disabled(isDetecting)
      FFmpegFolderProblemLabel(status: settings.customStatus)
      if detectionFoundNothing {
        Text("Couldn’t find another ffmpeg in the usual places.", bundle: #bundle)
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings.ffmpegAutoDetectResult")
      }
    }
  }

  private func chooseFolder() {
    detectionFoundNothing = false
    if let url = FilePanels.chooseFolder() {
      env.ffmpegSettings.customDirectory = url.path(percentEncoded: false)
    }
  }

  /// Adopts the best `ffmpeg` already installed, leaving the choice alone when there is none.
  private func detect() {
    isDetecting = true
    detectionFoundNothing = false
    Task {
      defer { isDetecting = false }
      guard let best = await FFmpegDiscovery.best() else {
        detectionFoundNothing = true
        return
      }
      env.ffmpegSettings.customDirectory = best.directory.path(percentEncoded: false)
    }
  }
}

/**
 What the chosen folder is short of, and nothing at all when it can serve —
 the version below already says which build is in use, so a second line
 confirming the folder is fine only takes up room.
 */
private struct FFmpegFolderProblemLabel: View {
  let status: FFmpegFolderStatus

  var body: some View {
    if let problem {
      Label(problem, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .font(.callout)
        .accessibilityIdentifier("settings.ffmpegCustomStatus")
    }
  }

  private var problem: String? {
    switch status {
      case .complete, .notChosen:
        nil
      case .missingFFmpeg:
        String(localized: "This folder contains ffprobe but not ffmpeg", bundle: #bundle)
      case .missingFFprobe:
        String(localized: "This folder contains ffmpeg but not ffprobe", bundle: #bundle)
      case .missingBoth:
        String(localized: "This folder must contain ffmpeg and ffprobe", bundle: #bundle)
    }
  }
}

/**
 What the resolved build turned out to be: its version, and a way into the
 full list of formats it supports.
 */
private struct FFmpegInformationSection: View {
  @Environment(AppEnvironment.self)
  private var env
  @State private var showingFormats = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("FFmpeg Information", bundle: #bundle)
      FFmpegVersionRow(state: env.capabilities.state)
      Button {
        showingFormats = true
      } label: {
        Text("Supported Formats", bundle: #bundle)
      }
      .accessibilityIdentifier("settings.ffmpegFormats")
      .disabled(!env.capabilities.state.isLoaded)
    }
    .sheet(isPresented: $showingFormats) {
      FFmpegFormatsSheet(
        store: env.capabilities,
        showsFullVersionLink: env.featureFlags.isAppStoreBuild
      )
    }
  }
}

/**
 Shows the resolved `ffmpeg` build's version, or the probe's progress and
 any "not runnable" reason.
 */
struct FFmpegVersionRow: View {
  let state: FFmpegCapabilitiesStore.State

  var body: some View {
    switch state {
      case .idle, .loading:
        HStack {
          ProgressView().controlSize(.small)
          Text("Reading version…", bundle: #bundle).foregroundStyle(.secondary)
        }
      case .loaded(let capabilities):
        LabeledContent("Version") {
          Text(capabilities.version?.version ?? String(localized: "Unknown", bundle: #bundle))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      case .unavailable(let reason):
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .font(.callout)
    }
  }
}

extension FFmpegCapabilitiesStore.State {
  /// Whether a probe has produced capabilities ready to display.
  var isLoaded: Bool {
    if case .loaded = self { return true }
    return false
  }
}

#if DEBUG
  #Preview("FFmpeg Version — states") {
    VStack(alignment: .leading, spacing: 12) {
      FFmpegVersionRow(state: .loading)
      FFmpegVersionRow(
        state: .loaded(
          FFmpegCapabilities(
            version: FFmpegVersionInfo(
              version: "6.1.1",
              bannerLine: "ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers",
              configuration: "--enable-gpl --enable-libx265",
              libraryVersions: []
            ),
            containers: [],
            videoCodecs: [],
            audioCodecs: [],
            subtitleCodecs: []
          )
        )
      )
      FFmpegVersionRow(state: .unavailable("Couldn’t run ffmpeg"))
      Spacer()
    }
    .padding()
    .frame(width: 480, height: 260, alignment: .topLeading)
  }

  #Preview("FFmpeg Folder Problems — states") {
    VStack(alignment: .leading, spacing: 12) {
      // .complete and .notChosen render nothing, so neither appears here.
      FFmpegFolderProblemLabel(status: .missingFFprobe)
      FFmpegFolderProblemLabel(status: .missingFFmpeg)
      FFmpegFolderProblemLabel(status: .missingBoth)
      Spacer()
    }
    .padding()
    .frame(width: 480, height: 160, alignment: .topLeading)
  }

  #Preview("FFmpeg Tab — App Store (gated)") {
    FFmpegSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: true))
      .frame(width: 480, height: 340)
  }

  #Preview("FFmpeg Tab — Built-in (download)") {
    FFmpegSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
      .frame(width: 480, height: 340)
  }

  #Preview("FFmpeg Tab — Custom (download)") {
    let env = settingsPreviewEnvironment(isAppStoreBuild: false)
    // An empty customDirectory leaves the picker in the orange "must contain
    // ffmpeg and ffprobe" state; a green "valid custom" state would require real
    // ffmpeg/ffprobe files on disk, which a preview can't provide.
    env.ffmpegSettings.mode = .custom
    return FFmpegSettingsTab()
      .environment(env)
      .frame(width: 480, height: 340)
  }
#endif
