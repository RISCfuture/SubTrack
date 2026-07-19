import XCTest
import XCUITestKit

/**
 Launches the Mac App Store build in stubbed UI-test mode. The same harness the
 download suite uses, but here `XCUIApplication` targets the MAS app, whose
 `FeatureFlags.isAppStoreBuild` is `true` — so this suite sees the gated UI.
 */
enum MASApp {
  static func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-uiTesting"]
    app.launchEnvironment["UITEST_STATE"] = "empty"
    app.launchAndWaitUntilReady(readyElement: { $0.descendant(id: "toolbar.add") })
    return app
  }
}

/**
 A slim Settings driver for the gating suite: open, switch tab, and assert an
 identifier is present or absent.
 */
struct MASSettingsScreen {
  let app: XCUIApplication

  @discardableResult
  func open() -> Self {
    app.openSettings()
    return self
  }

  @discardableResult
  func showTab(_ name: String) -> Self {
    app.selectSettingsTab(name)
    return self
  }

  func assertVisible(_ identifier: String) {
    app.descendant(id: identifier)
      .assertExists("Expected “\(identifier)” to be present in the App Store build.")
  }

  func assertAbsent(_ identifier: String) {
    app.descendant(id: identifier)
      .assertNeverAppears("“\(identifier)” should be gated off in the App Store build.")
  }
}
