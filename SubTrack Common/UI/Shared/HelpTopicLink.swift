import SwiftUI

/**
 The system help button — a circled question mark — pointed at one topic in
 the app's help book.

 Wraps `HelpLink` rather than replacing it: that is the real AppKit control,
 and hand-rolling one gets the metrics, the focus ring, and the hover
 treatment subtly wrong. What `HelpLink` doesn't supply is everything around
 it. It labels itself "Help", identically, however many are on screen — six
 are, in the Settings window — and it carries no identifier for the UI tests
 to find. Both come from the anchor's own ``HelpAnchor/accessibilityLabel``
 and the caller's screen, and pairing them by hand at every call site is how
 they come apart.

 Inherits `controlSize` from its container, so the same view is a full-size
 button in a Settings pane and a small one in the inspector, where
 ``InspectorForm`` brings the whole tab down a step.
 */
struct HelpTopicLink: View {
  /// The topic in the book this button opens.
  let anchor: HelpAnchor

  /**
   Names the surface the button sits on, in the app's `<screen>.<control>`
   scheme — deliberately not derived from the anchor, which names a topic
   instead and is shared by every surface asking the same question.
   */
  let accessibilityIdentifier: String

  var body: some View {
    HelpLink(anchor: anchor.rawValue)
      .help(anchor.accessibilityLabel)
      .accessibilityLabel(anchor.accessibilityLabel)
      .accessibilityIdentifier(accessibilityIdentifier)
  }
}

#if DEBUG
  // Clicking does nothing here: a preview host registers no help book, so
  // `HelpLink` has nothing to open. These check the metrics — where the button
  // sits, and that a container's `controlSize` reaches it.
  #Preview("Help topic link") {
    Form {
      LabeledContent("Codec set") {
        Text("Full (all codecs)").foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HelpTopicLink(anchor: .settingsEncoding, accessibilityIdentifier: "preview.help")
        .padding([.trailing, .bottom], 16)
    }
    .frame(width: 420, height: 220)
  }

  #Preview("Help topic link — small") {
    HelpTopicLink(anchor: .slimRules, accessibilityIdentifier: "preview.help")
      .controlSize(.small)
      .padding()
  }
#endif
