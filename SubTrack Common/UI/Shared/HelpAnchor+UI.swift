import AppKit

extension HelpAnchor {

  /**
   The help book this app bundle registered, read from `Info.plist` rather
   than written here.

   The framework is loaded into two app bundles that ship the same book under
   different identifiers, so there is no one right answer to compile in.
   `Bundle.main` is the app in both cases — never the framework, which ships no
   book of its own.
   */
  private static var bookName: NSHelpManager.BookName? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? NSHelpManager.BookName
  }

  /**
   What a control pointing here is about, for VoiceOver and the tooltip.

   `HelpLink` labels itself "Help" and offers no way to say more, which in a
   six-pane Settings window means six identical buttons with nothing to tell
   them apart. Each label is a whole sentence rather than "Help with" plus a
   noun, because the preposition inflects in languages that decline.
   */
  var accessibilityLabel: String {
    switch self {
      case .gettingStarted:
        String(localized: "Read how SubTrack works", bundle: #bundle, comment: "Help button label")
      case .slimRules:
        String(localized: "Help with keep rules", bundle: #bundle, comment: "Help button label")
      case .trackOverrides:
        String(
          localized: "Help with per-file overrides",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .settingsGeneral:
        String(
          localized: "Help with output destinations",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .presets:
        String(localized: "Help with presets", bundle: #bundle, comment: "Help button label")
      case .presetSync:
        String(localized: "Help with preset syncing", bundle: #bundle, comment: "Help button label")
      case .settingsEncoding:
        String(
          localized: "Help with encoding settings",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .settingsFFmpeg:
        String(
          localized: "Help with FFmpeg settings",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .supportedFormats:
        String(
          localized: "Help with supported formats",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .commandLineTool:
        String(
          localized: "Help with the command-line tool",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .settingsUpdates:
        String(localized: "Help with update checks", bundle: #bundle, comment: "Help button label")
      case .editions:
        String(
          localized: "Help with the two editions of SubTrack",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .nameConflicts:
        String(
          localized: "Help with output name conflicts",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .unsupportedCodec:
        String(
          localized: "Help with unsupported codecs",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .troubleshooting:
        String(localized: "Help with a failed file", bundle: #bundle, comment: "Help button label")
      case .customFFmpeg:
        String(
          localized: "Help with choosing an FFmpeg build",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .cliInstall:
        String(
          localized: "Help with installing the command-line tool",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .probeFailed:
        String(
          localized: "Help with unreadable files",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .missingSource:
        String(
          localized: "Help with missing source files",
          bundle: #bundle,
          comment: "Help button label"
        )
      case .encodeFailed:
        String(localized: "Help with failed encodes", bundle: #bundle, comment: "Help button label")
    }
  }

  /**
   Opens the help book at this topic.

   For the affordances a `HelpLink` can't be: one that has to sit inline
   against a line of text at glyph size, and one that reads as a sentence
   rather than a question mark. Panes use ``HelpTopicLink``, which is the real
   system control.
   */
  @MainActor
  func open() {
    NSHelpManager.shared.openHelpAnchor(rawValue, inBook: Self.bookName)
  }
}
