import XCTest
import XCUITestKit

/// Settings, the Activity Log and About windows, and menu/keyboard-driven commands.
nonisolated final class WindowsUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
}

@MainActor
extension WindowsUITests {
  func testSettingsTabNavigation() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    // showTab confirms each switch via the window title; assert representative
    // content on the two tabs whose controls reliably surface to accessibility.
    let settings = SettingsScreen(app: app).open()
    settings.showTab("Encoding")
    settings.assertVisible("settings.maxConcurrent")
    settings.showTab("FFmpeg")
    settings.assertVisible("settings.ffmpegFormats")
    settings.showTab("Presets")
    settings.assertVisible("settings.presetList")
    settings.showTab("CLI")
    settings.showTab("General")
  }

  func testSupportedFormatsSheet() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("FFmpeg")
    settings.openSupportedFormats()

    settings.assertSheetAppears()
  }

  func testActivityLogWindow() {
    let app = SubTrack.launch(state: .oneReadyItem)
    MainWindowScreen(app: app).waitUntilLoaded()

    ActivityLogScreen(app: app).open().assertTableVisible()
  }

  func testAboutWindow() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    AboutScreen(app: app).open().assertWindowVisible()
  }

  /// The build's FFmpeg license has to be reachable, which is why About is custom.
  func testAboutLicenseSheet() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    AboutScreen(app: app).open().openLicense().assertLicenseSheetVisible()
  }

  /**
   The status bar is the only place the queue reports itself as a whole, and
   the progress bar joins it only while work is in flight.
   */
  func testStatusBarSummarizesTheQueue() {
    let app = SubTrack.launch(state: .oneReadyItem, stepDelayMilliseconds: 1500)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.assertItemCount(1)
    window.overallProgress.assertHidden("An idle queue shows no overall progress.")

    window.startAll()

    window.overallProgress.assertExists("A running queue should show its overall progress.")
    window.assertItemFinished()
    XCTAssertTrue(
      window.statusSummary.waitFor(NSPredicate(format: "value CONTAINS %@", "slimmed")),
      "A finished item should be counted as slimmed."
    )
  }

  /// A finished run measures its output, which the table reports beside the input size.
  func testFinishedItemReportsItsOutputSize() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.startAll()
    window.assertItemFinished()

    XCTAssertFalse(
      (window.outputSize.value as? String ?? "").isEmpty,
      "A finished item should report the size of what it wrote."
    )
  }

  func testStartAllViaKeyboardCommand() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    app.typeKey("r", modifierFlags: .command)

    window.assertItemFinished()
  }
}
