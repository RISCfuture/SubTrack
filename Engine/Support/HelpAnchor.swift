import Foundation

/**
 A named place in the app's help book.

 Every help affordance names one of these rather than a bare string. The
 anchors themselves are `<a name="…">` elements in the HTML under
 `Help/SubTrack.help`, and nothing at compile time can catch a typo: a
 misspelled anchor doesn't fail, it silently opens the book's first page
 instead of the topic the user asked for — the kind of wrongness nobody
 bothers to report. Naming them once here is what lets
 `Scripts/build-help-book.sh` check each one against the book it is about to
 ship, and fail the build when the two disagree.

 The raw values name the *concept* rather than the control that points at one,
 so moving a setting between panes never invalidates an anchor, and two
 surfaces asking the same question can share one. They are identifiers, not
 prose, and are never translated — a localized book repeats these same names
 in every `.lproj`.

 This sits beside the errors that name it rather than beside the views because
 `Engine` compiles into the command-line tool as well as the app, and an
 AppKit dependency here would not. Opening a book is a `SubTrack Common`
 concern; knowing which page to ask for is not.
 */
enum HelpAnchor: String, Sendable {

  // MARK: - Topics the interface links to

  /// What the app is for, and why copying beats re-encoding.
  case gettingStarted = "what-subtrack-does"

  /// The queue-wide keep-rules: languages, untagged tracks, commentary.
  case slimRules = "slim-rules"

  /// One file's own track-by-track departures from the queue's rules.
  case trackOverrides = "track-overrides"

  /// Where slimmed files are written, and the default new queues inherit.
  case settingsGeneral = "settings-general"

  /// Saved rule sets: the starters, and saving rules as a new one.
  case presets = "presets"

  /// Why presets stop syncing, and what each reason means.
  case presetSync = "sync-unavailable"

  /// How many files encode at once, and which codec set this build ships.
  case settingsEncoding = "settings-encoding"

  /// Which `ffmpeg` the app runs.
  case settingsFFmpeg = "settings-ffmpeg"

  /// Reading the containers and codecs a resolved build reports.
  case supportedFormats = "supported-formats"

  /// Installing and using the `subtrack` command-line tool.
  case commandLineTool = "subtrack-cli"

  /// The downloadable build's update checks.
  case settingsUpdates = "settings-updates"

  /// What separates the App Store build from the downloadable one.
  case editions = "editions"

  /// The two ways a set of output names can collide.
  case nameConflicts = "name-conflicts"

  /// What to do when the resolved build can't encode a chosen codec.
  case unsupportedCodec = "unsupported-codec"

  /// Reading a failure, and where the untruncated error survives.
  case troubleshooting = "troubleshooting"

  // MARK: - Topics only a failure names

  /// Pointing the app at an `ffmpeg` build of your own.
  case customFFmpeg = "custom-ffmpeg"

  /// Installing the command-line tool, including the privileged case.
  case cliInstall = "cli-install"

  /// When `ffprobe` refuses to read a source file.
  case probeFailed = "probe-failed"

  /// When a source file has moved out from under the queue.
  case missingSource = "missing-source"

  /// When `ffmpeg` starts and then fails partway.
  case encodeFailed = "encode-failed"
}
