import XCTest

/**
 Asserts the App Store build gates off the features App-Store policy forbids —
 a custom ffmpeg location and the CLI installer — replacing each with a link to
 the downloadable build. The full flow behaviour is covered by the download
 suite; this asserts only the differences.
 */
final class MASGatingUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  func testFFmpegLocationIsLocked() {
    let app = MASApp.launch()
    let settings = MASSettingsScreen(app: app).open()
    settings.showTab("FFmpeg")

    // The App Store build replaces the custom-location controls with a link to
    // the downloadable build; the download build shows no such link here.
    settings.assertVisible("settings.fullVersionHelp")
    settings.assertAbsent("settings.ffmpegChoose")
  }

  func testCLIInstallIsUnavailable() {
    let app = MASApp.launch()
    let settings = MASSettingsScreen(app: app).open()
    settings.showTab("CLI")

    settings.assertVisible("settings.fullVersionHelp")
    settings.assertAbsent("settings.cliInstall")
  }

  func testCodecSetShowsFullVersionLink() {
    let app = MASApp.launch()
    let settings = MASSettingsScreen(app: app).open()
    settings.showTab("Encoding")

    settings.assertVisible("settings.fullVersionHelp")
  }
}
