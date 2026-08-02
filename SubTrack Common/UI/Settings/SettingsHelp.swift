import SwiftUI

/**
 Where a Settings pane's help button sits: far enough in to line up with the
 content above it rather than floating in the window's corner.
 */
private enum SettingsHelpInsets {
  static let trailing: Double = 20
  static let bottom: Double = 16
}

extension View {

  /**
   Puts the pane's help button where macOS puts one — bottom-trailing, below
   the content, on the pane's own background.

   `safeAreaInset` rather than `overlay`, because the tabs are three different
   shapes and only one of them could afford to be covered. Three are grouped
   `Form`s that scroll once they fill, two are bare stacks, and the Presets tab
   is a list-and-editor split whose bottom-trailing corner already holds Delete
   Preset — the one destructive control in the window. An overlay would float
   over that button, and over the last row of any form long enough to scroll. A
   bottom inset reserves the strip instead, and a grouped `Form`'s scroll view
   honours it, so its rows scroll clear rather than under.

   - Parameters:
     - anchor: The topic in the help book that explains this pane.
     - accessibilityIdentifier: Names the pane, in the app's
       `<screen>.<control>` scheme, so a test can tell six otherwise identical
       buttons apart.
   */
  func settingsHelp(
    _ anchor: HelpAnchor,
    accessibilityIdentifier: String
  ) -> some View {
    safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
      HelpTopicLink(anchor: anchor, accessibilityIdentifier: accessibilityIdentifier)
        .padding(.trailing, SettingsHelpInsets.trailing)
        .padding(.bottom, SettingsHelpInsets.bottom)
    }
  }
}
