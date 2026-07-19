import SwiftUI

/**
 A small "?" that links to the page explaining the downloadable, full-featured
 build of SubTrack. Shown next to controls disabled in the App Store build.
 */
struct FullVersionHelpLink: View {
  var body: some View {
    Link(destination: FeatureFlags.fullVersionURL) {
      Image(systemName: "questionmark.circle")
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help("Available in the downloadable version of SubTrack. Click to learn more.")
    .accessibilityLabel("Why is this unavailable?")
    .accessibilityIdentifier("settings.fullVersionHelp")
  }
}

#Preview {
  Form {
    LabeledContent("Some feature") {
      HStack(spacing: 6) {
        Text("Built-in").foregroundStyle(.secondary)
        FullVersionHelpLink()
      }
    }
  }
  .formStyle(.grouped)
  .padding()
}
