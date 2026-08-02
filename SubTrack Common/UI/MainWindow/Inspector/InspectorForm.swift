import SwiftUI

/**
 The margins the inspector's header row sits in, which its help button shares
 so the two line up against the same edge.
 */
private enum InspectorHeaderInsets {
  static let horizontal: Double = 12
  static let vertical: Double = 8
}

/**
 The shape every inspector tab shares: the control that picks what the tab is
 about, sitting full-width above the tab's body rather than inside it, the help
 button for whatever the tab as a whole is about, and the body itself.

 `controlSize` is the density control — it propagates through the environment
 and brings every toggle, picker, button, and field in the tab down a step,
 labels included, without freezing a type size the system should own. The help
 button rides that down with everything else.

 Most tabs describe a thing with small controls and want ``InspectorForm``.
 This is for the ones whose body is not a form.
 */
struct InspectorPane<Header: View, Content: View>: View {
  /// What the tab as a whole is about, for the help button beside its header.
  let helpAnchor: HelpAnchor

  /// Tells the tabs' otherwise identical help buttons apart.
  let helpAccessibilityIdentifier: String

  @ViewBuilder let header: Header
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        header
          .frame(maxWidth: .infinity)
        HelpTopicLink(
          anchor: helpAnchor,
          accessibilityIdentifier: helpAccessibilityIdentifier
        )
      }
      .padding(.horizontal, InspectorHeaderInsets.horizontal)
      .padding(.vertical, InspectorHeaderInsets.vertical)
      Divider()
      content
    }
    .controlSize(.small)
  }
}

/// An ``InspectorPane`` whose body is a form of small controls.
struct InspectorForm<Header: View, Content: View>: View {
  /// What the tab as a whole is about, for the help button beside its header.
  let helpAnchor: HelpAnchor

  /// Tells the tabs' otherwise identical help buttons apart.
  let helpAccessibilityIdentifier: String

  @ViewBuilder let header: Header
  @ViewBuilder let content: Content

  var body: some View {
    InspectorPane(
      helpAnchor: helpAnchor,
      helpAccessibilityIdentifier: helpAccessibilityIdentifier
    ) {
      header
    } content: {
      Form { content }
        .formStyle(.grouped)
    }
  }
}

/**
 Controls that belong together, laid out as a single form row so the form
 doesn't rule a line between things the user reads as one setting.
 */
struct InspectorGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) { content }
  }
}

/// A line of explanation under the control it belongs to.
struct InspectorCaption: View {
  let text: LocalizedStringKey

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  init(_ text: LocalizedStringKey) {
    self.text = text
  }
}

/**
 A section's title, with what the section is for behind an info button rather
 than in a footer. A footer spends a permanent block of the pane restating
 something the user needs once; hovering the button asks for it instead.
 */
struct InspectorSectionHeader: View {
  private static let helpWidth = 220.0

  let title: LocalizedStringKey
  let help: LocalizedStringKey

  @State private var showingHelp = false

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("About this section", bundle: #bundle))
        .onHover { showingHelp = $0 }
        .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
          Text(help)
            .font(.caption)
            .frame(maxWidth: Self.helpWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
        }
    }
  }
}

/**
 A control and the line explaining it, as one form row — so the caption reads
 as part of its control rather than as a setting of its own.
 */
struct CaptionedControl<Control: View>: View {
  let caption: LocalizedStringKey
  @ViewBuilder let control: Control

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      control
      InspectorCaption(caption)
    }
  }

  init(_ caption: LocalizedStringKey, @ViewBuilder control: () -> Control) {
    self.caption = caption
    self.control = control()
  }
}

extension View {

  /**
   Draws a toggle as a checkbox rather than the switch a grouped `Form` gives
   it by default. A switch is a chunk of chrome the width of a word, pinned to
   the far side of the row; a checkbox sits against its own label at the size
   of the surrounding text, which is what this pane's density needs.
   */
  func inspectorCheckbox() -> some View {
    toggleStyle(.checkbox)
  }
}

#if DEBUG
  #Preview("Inspector Form") {
    InspectorForm(helpAnchor: .slimRules, helpAccessibilityIdentifier: "preview.rulesHelp") {
      Menu("Preset — Everyday") {
        Button("Everyday") {}
      }
    } content: {
      Section {
        CaptionedControl("Tracks in any other language are dropped from the output.") {
          Toggle("Keep only preferred languages", isOn: .constant(true))
            .inspectorCheckbox()
        }
        InspectorGroup {
          Toggle("Keep forced subtitles", isOn: .constant(true))
            .inspectorCheckbox()
          Toggle("Keep commentary tracks", isOn: .constant(false))
            .inspectorCheckbox()
        }
      } header: {
        InspectorSectionHeader(
          title: "Languages",
          help: "Hover the info button to read what a section does, in place of a footer."
        )
      }
    }
    .frame(width: 320, height: 260)
  }
#endif
