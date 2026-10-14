import XCTest
import XCUITestKit

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
