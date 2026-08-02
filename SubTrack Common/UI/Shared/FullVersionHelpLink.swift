import SwiftUI

/**
 A small "?" opening the help book's page on what separates the two editions.
 Shown next to controls disabled in the App Store build.

 A bare glyph rather than the ``HelpTopicLink`` the panes use, because this one
 sits inline in a line of text, where a bezeled button is a lump — and because
 each of these tabs carries a pane-level help button of its own, which this
 must not read as a second copy of.

 It opens the manual rather than the site: the answer is three specific
 capabilities and where each control lives, which is a page of the manual, and
 reading it shouldn't cost a sandboxed app a trip out to a browser. The
 download links live on that page.
 */
struct FullVersionHelpLink: View {
  var body: some View {
    Button {
      HelpAnchor.editions.open()
    } label: {
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
