import AppKit
import SwiftUI

/**
 The custom About window: app identity plus the per-build FFmpeg
 acknowledgement and license.
 */
struct AboutView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    AboutContent(
      info: .current,
      acknowledgement: .forBuild(fullCodecSet: env.featureFlags.fullCodecSet)
    )
  }

  init() {}
}

private struct AboutContent: View {
  /**
   The About panel is a fixed-size card, so it carries a roomier inset than
   the default one that suits content filling a resizable window.
   */
  private static let panelInset: CGFloat = 24

  let info: AppInfo
  let acknowledgement: FFmpegAcknowledgement
  @State private var showingLicense = false

  var body: some View {
    VStack {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityLabel("SubTrack app icon")

      VStack(spacing: 4) {
        Text(info.name).font(.title2).bold()
        Text("Version \(info.version) (\(info.build))")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(info.copyright)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .textSelection(.enabled)

      Divider()

      ScrollView {
        Text(acknowledgement.summary)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 120)

      HStack {
        Button("License…") { showingLicense = true }
          .accessibilityIdentifier("about.license")
        Link("FFmpeg.org", destination: URL(string: "https://www.ffmpeg.org")!)
      }
    }
    .padding(Self.panelInset)
    .frame(width: 380)
    .sheet(isPresented: $showingLicense) {
      LicenseSheet(acknowledgement: acknowledgement)
    }
  }
}

#Preview("Download (GPL)") {
  AboutContent(info: .current, acknowledgement: .gpl)
}

#Preview("App Store (LGPL)") {
  AboutContent(info: .current, acknowledgement: .lgpl)
}
