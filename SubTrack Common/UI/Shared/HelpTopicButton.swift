import SwiftUI

/**
 A link offering the help-book page about something that has just gone wrong.

 The counterpart to ``HelpTopicLink``, for a different moment. A circled
 question mark beside a pane says *this screen has a manual page*; this says
 *this particular thing failed, and there is a page about it*. It follows a
 warning, so it is a sentence rather than a glyph, and set at the warning's own
 `.caption` scale — a bezeled `HelpLink` next to a caption-sized label in a
 300pt inspector is louder than the warning it annotates.

 The anchor isn't optional, so a surface with nothing useful to point at simply
 doesn't build one. A help button that lands on a general page is worse than no
 help button.
 */
struct HelpTopicButton: View {
  /// The topic in the book explaining the failure this sits under.
  let anchor: HelpAnchor

  /// Names the surface the button sits on, in the `<screen>.<control>` scheme.
  let accessibilityIdentifier: String

  var body: some View {
    Button(LocalizedStringResource("Get help with this.", bundle: #bundle)) { anchor.open() }
      .buttonStyle(.link)
      .font(.caption)
      .accessibilityIdentifier(accessibilityIdentifier)
  }
}

#if DEBUG
  #Preview("Help topic button") {
    VStack(alignment: .leading, spacing: 2) {
      Label(
        "The current FFmpeg can’t encode “libx265”.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.orange)
      .font(.caption)
      HelpTopicButton(anchor: .unsupportedCodec, accessibilityIdentifier: "preview.helpButton")
    }
    .padding()
    .frame(width: 300, alignment: .leading)
  }
#endif
