import XCTest
import XCUITestKit

/// The Settings window's tabs, driving the controls rather than just finding them.
nonisolated final class SettingsUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
}

@MainActor
extension SettingsUITests {
  func testChangeSimultaneousEncodes() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("Encoding")
    settings.choose("4", from: "settings.maxConcurrent")

    XCTAssertEqual(
      settings.value(of: "settings.maxConcurrent"),
      "4",
      "The concurrency picker should hold the chosen value."
    )
  }

  func testChangeDefaultDestination() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("General")
    settings.click("settings.generalDestination")

    let destinationLabel = app.staticTexts
      .containing(NSPredicate(format: "value CONTAINS %@", "UITestFixtures/destination"))
      .firstMatch
    XCTAssertTrue(
      destinationLabel.wait(),
      "The General tab should show the chosen default destination."
    )
  }

  /**
   Choosing a custom `ffmpeg` folder that holds no binaries must say so rather
   than silently accept it — the harness's folder fixture is exactly such a
   folder.
   */
  func testCustomFFmpegFolderReportsMissingBinaries() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("FFmpeg")
    settings.click("settings.ffmpegModeCustom")

    // Offered alongside Choose…, but not exercised: what it finds depends on
    // what this Mac happens to have installed.
    settings.assertVisible("settings.ffmpegAutoDetect")
    settings.assertVisible("settings.ffmpegChoose")
    settings.click("settings.ffmpegChoose")

    // By value, not label: a SwiftUI Label surfaces its string as the element's value.
    XCTAssertTrue(
      app.descendant(id: "settings.ffmpegCustomStatus").waitFor(
        NSPredicate(format: "value CONTAINS[c] %@", "must contain")
      ),
      "A folder without ffmpeg and ffprobe should be reported as unusable."
    )
  }

  /**
   The download build offers the CLI installer the App Store build replaces
   with a link (asserted absent in the MAS suite). Install itself opens a
   folder panel this harness doesn't stub, so only the copy path is clicked.
   */
  func testCLIInstallIsOffered() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("CLI")

    settings.assertVisible("settings.cliInstall")
    settings.assertAbsent("settings.fullVersionHelp")
    settings.click("settings.cliCopyCommand")
  }

  func testSupportedFormatsSheetFilters() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("FFmpeg")
    settings.openSupportedFormats()

    let formats = FormatsSheetScreen(app: app)
    formats.assertEntry("h264")
    formats.filter("aac")

    formats.assertEntry("aac")
    formats.assertNoEntry("h264")
  }
}
