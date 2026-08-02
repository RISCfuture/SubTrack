import XCTest
import XCUITestKit

/**
 Launches the app in stubbed UI-test mode. Every test starts here, so the
 `-uiTesting` argument and fixture configuration live in one place rather than
 being repeated per test.
 */
enum SubTrack {

  static func launch(
    state: State = .empty,
    engine: Engine = .succeed,
    stepDelayMilliseconds: Int? = nil,
    probeDelayMilliseconds: Int? = nil,
    largeFolderSize: Int? = nil,
    appearance: Appearance? = nil,
    windowSize: CGSize? = nil,
    ffmpegFolder: FFmpegFolder = .missing
  ) -> XCUIApplication {
    let app = XCUIApplication()
    // Every switch carries a value, including the bare-looking `-uiTesting`. The
    // argument domain reads the token after a `-key` as that key's value, so a
    // valueless switch swallows the switch that follows it and neither takes
    // effect.
    app.launchArguments += ["-uiTesting", "YES"]
    // AppKit reopens the windows a launch left behind rather than the ones the
    // scene declares. A test-run app is killed rather than quit, so what it
    // leaves is whatever it happened to be holding — and a launch that leaves
    // nothing brings the next one up with no main window at all. Ignoring the
    // saved state makes every launch open the scene as declared.
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    app.launchEnvironment["UITEST_STATE"] = state.rawValue
    app.launchEnvironment["UITEST_ENGINE"] = engine.rawValue
    app.launchEnvironment["UITEST_FFMPEG_FOLDER"] = ffmpegFolder.rawValue
    if let stepDelayMilliseconds {
      app.launchEnvironment["UITEST_STEP_DELAY_MS"] = String(stepDelayMilliseconds)
    }
    if let probeDelayMilliseconds {
      app.launchEnvironment["UITEST_PROBE_DELAY_MS"] = String(probeDelayMilliseconds)
    }
    if let largeFolderSize {
      app.launchEnvironment["UITEST_LARGE_FOLDER"] = String(largeFolderSize)
    }
    if let appearance { stageForScreenshots(app, in: appearance) }
    if let windowSize {
      app.launchEnvironment["UITEST_WINDOW_SIZE"] =
        "\(Int(windowSize.width))x\(Int(windowSize.height))"
    }
    // The toolbar's Add control is present whether the queue is empty or populated,
    // so it's the stable "window is up" signal.
    app.launchAndWaitUntilReady(readyElement: { $0.descendant(id: "toolbar.add") })
    return app
  }

  /**
   Turns on the harness's screenshot staging and settles the two things on
   screen that move on their own: an overlay scrollbar fading out after a
   scroll, and a text field's blinking insertion point. Both settings live in
   `NSGlobalDomain`, which the argument domain outranks, so neither touches the
   developer's own preferences.
   */
  private static func stageForScreenshots(_ app: XCUIApplication, in appearance: Appearance) {
    app.launchEnvironment["UITEST_SCREENSHOTS"] = "1"
    app.launchEnvironment["UITEST_APPEARANCE"] = appearance.rawValue
    app.launchArguments += ["-AppleShowScrollBars", "WhenScrolling"]
    app.launchArguments += ["-NSTextInsertionPointBlinkPeriodOff", "999999"]
  }

  /// The queue arrangement the harness seeds at launch (mirrors `UITEST_STATE`).
  enum State: String {
    case empty
    case oneReadyItem
    case multiQueue

    /**
     Two sources that share a file name but not a folder, saved into one
     destination — the arrangement the default output-name format collides on.
     */
    case duplicateNames

    /// One item whose source is deleted once it has been added.
    case missingSource

    /// One item under rules that keep none of its audio.
    case audioLoss

    /// One item whose plan needs an encoder the resolved build doesn't have.
    case incompatible

    /// The Help book's queue: eight Blu-ray rips part-way through a run.
    case helpQueue

    /// The Help book's troubleshooting queue: four distinct troubles at once.
    case helpProblems
  }

  /// How stubbed runs resolve (mirrors `UITEST_ENGINE`).
  enum Engine: String {
    case succeed
    case fail
  }

  /**
   The appearance the whole app process is pinned to (mirrors
   `UITEST_APPEARANCE`). Asking for one also stages the app for capture, so
   only the screenshot suite pays for any of it.
   */
  enum Appearance: String {
    case light
    case dark
  }

  /// What the harness's folder chooser hands back (mirrors `UITEST_FFMPEG_FOLDER`).
  enum FFmpegFolder: String {
    /// A folder holding neither `ffmpeg` nor `ffprobe`, which Settings rejects.
    case missing

    /// A folder holding both binaries, which Settings accepts.
    case valid
  }
}
