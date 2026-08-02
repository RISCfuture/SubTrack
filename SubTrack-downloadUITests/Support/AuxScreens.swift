import XCTest
import XCUITestKit

/// Drives the Settings window (⌘,) and its tabs.
struct SettingsScreen {
  let app: XCUIApplication

  /**
   The Settings window itself, so a screenshot can frame the whole pane. Found
   by identifier rather than title, which tracks the selected tab.
   */
  var window: XCUIElement {
    app.windows.matching(identifier: XCUIApplication.settingsWindowIdentifier).firstMatch
  }

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

  /// Closes the Settings window, so a test can go back to the main window.
  @discardableResult
  func close() -> Self {
    app.typeKey("w", modifierFlags: .command)
    return self
  }

  /**
   Opens the Supported Formats sheet. The button stays disabled until the
   resolved build has actually been probed, which is a real subprocess and much
   slower than the window, so this waits for it to come alive rather than
   clicking into a disabled control.

   Scoped to `buttons`: the button's label is a plain `Text`, so SwiftUI copies
   the identifier onto the static text inside it, and an untyped descendant
   query resolves to that instead. It reports `isEnabled == true` like the
   button does, so the wait below passes and the click silently lands on a
   label that opens nothing.
   */
  @discardableResult
  func openSupportedFormats() -> Self {
    let button = app.buttons["settings.ffmpegFormats"].firstMatch
      .assertExists("The Supported Formats button is missing.")
    XCTAssertTrue(
      button.waitFor(NSPredicate(format: "isEnabled == true"), timeout: ScaledTimeouts.slowElement),
      "The Supported Formats button never enabled — no ffmpeg build was probed."
    )
    button.click()
    return self
  }

  @discardableResult
  func click(_ identifier: String) -> Self {
    app.descendant(id: identifier).assertExists("Expected “\(identifier)” in Settings.").click()
    return self
  }

  /**
   Picks `option` from the menu-style Picker identified by `identifier`. A
   radio-group Picker is driven by clicking its option's own identifier
   instead — SwiftUI gives every radio button the Picker's identifier too.
   */
  @discardableResult
  func choose(_ option: String, from identifier: String) -> Self {
    app.descendant(id: identifier).assertExists("Expected “\(identifier)” in Settings.").click()
    app.menuItems[option].firstMatch
      .assertExists("“\(option)” isn’t offered by “\(identifier)”.")
      .click()
    return self
  }

  func assertVisible(_ identifier: String) {
    app.descendant(id: identifier).assertExists("Expected “\(identifier)” in Settings.")
  }

  func assertAbsent(_ identifier: String) {
    app.descendant(id: identifier).assertHidden("“\(identifier)” should not be in Settings.")
  }

  func value(of identifier: String) -> String {
    (app.descendant(id: identifier).value as? String) ?? ""
  }

  func assertSheetAppears() {
    app.sheets.firstMatch.assertExists("The supported-formats sheet never appeared.")
  }
}

/**
 Drives the Presets tab: the list on the left and the selected preset's
 editable name, rules, and delete on the right.
 */
struct PresetsSettingsScreen {
  let app: XCUIApplication

  var nameField: XCUIElement { app.descendant(id: "settings.presetName") }

  @discardableResult
  func select(_ name: String) -> Self {
    app.staticText(value: name).assertExists("No preset named “\(name)” is listed.").click()
    return self
  }

  @discardableResult
  func rename(to name: String) -> Self {
    let field = nameField.assertExists("The preset name field isn’t shown.")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(name)
    // The edit is written through on each keystroke, but the field keeps focus;
    // Tab commits it the way leaving the field would.
    app.typeKey(.tab, modifierFlags: [])
    return self
  }

  /// Deletes the selected preset, confirming the dialog that follows.
  @discardableResult
  func deleteSelected() -> Self {
    app.descendant(id: "settings.deletePreset")
      .assertExists("The delete-preset button isn’t shown.")
      .click()
    app.sheets.firstMatch.buttons["Delete"]
      .assertExists("The delete-preset confirmation never appeared.")
      .click()
    return self
  }

  func assertListed(_ name: String) {
    app.staticText(value: name).assertExists("Preset “\(name)” should be listed.")
  }

  func assertNotListed(_ name: String) {
    app.staticText(value: name).assertHidden("Preset “\(name)” should be gone.")
  }
}

/// Drives the Supported Formats sheet opened from Settings ▸ FFmpeg.
struct FormatsSheetScreen {
  let app: XCUIApplication

  @discardableResult
  func filter(_ query: String) -> Self {
    let field = app.searchFields.firstMatch
      .assertExists("The formats sheet has no filter field.")
    field.click()
    field.typeText(query)
    return self
  }

  func assertEntry(_ identifier: String) {
    app.descendant(id: "formats.entry.\(identifier)")
      .assertExists("Expected “\(identifier)” in the formats list.")
  }

  func assertNoEntry(_ identifier: String) {
    app.descendant(id: "formats.entry.\(identifier)")
      .assertHidden("“\(identifier)” should be filtered out.")
  }
}

/**
 Drives the preset menu, shared by the inspector and toolbar. Its items live in
 a pop-up `Menu` (not the menu bar), so they are clicked as `menuItems` after
 opening rather than through `clickMenuItem`.
 */
struct PresetsScreen {
  let app: XCUIApplication

  /**
   The name the menu itself shows — the preset the queue's rules currently
   *are*, or "(New Preset)" when they match none.

   Scoped to `menuButtons` and read from `title`: the menu surfaces as a
   `MenuButton` carrying its name there rather than in `value`, and an untyped
   descendant query by this identifier resolves to a different element.
   */
  var activeName: String {
    app.menuButtons["presetMenu"].firstMatch.title
  }

  @discardableResult
  func openMenu() -> Self {
    app.descendant(id: "presetMenu").click()
    return self
  }

  /**
   Saves the queue's current rules as a preset called `name`.

   The menu item only opens a naming prompt — the preset isn't saved until that
   is confirmed. The prompt opens with its field focused on a suggested name
   derived from how many presets already exist, so the test types its own name
   over that suggestion rather than depending on the starter-preset count, and
   commits with Return (the prompt's Save button is the default).
   */
  @discardableResult
  func saveCurrentAsPreset(named name: String) -> Self {
    openMenu()
    app.menuItems["Save Current as Preset…"]
      .assertExists("“Save Current as Preset…” not found.")
      .click()

    let field = app.sheets.firstMatch.textFields.firstMatch
      .assertExists("The preset-name prompt never appeared.")
    field.typeKey("a", modifierFlags: .command)
    field.typeText(name)
    app.typeKey(.return, modifierFlags: [])
    return self
  }

  /// Applies a saved preset to the selected queue by clicking it in the menu.
  @discardableResult
  func apply(_ name: String) -> Self {
    openMenu()
    app.menuItems[name].firstMatch.assertExists("Preset “\(name)” not in the menu.").click()
    return self
  }

  /// Waits for the menu to settle on `name` as the queue's active preset.
  func assertActivePreset(_ name: String) {
    XCTAssertTrue(
      app.menuButtons["presetMenu"].firstMatch.waitFor(NSPredicate(format: "title == %@", name)),
      "Expected the preset menu to report “\(name)”, got “\(activeName)”."
    )
  }

  /// Waits for the menu to stop reporting `name`, as an edit away from it should.
  func assertNotActivePreset(_ name: String) {
    XCTAssertTrue(
      app.menuButtons["presetMenu"].firstMatch.waitFor(NSPredicate(format: "title != %@", name)),
      "The menu still reports “\(name)” after the rules moved away from it."
    )
  }

  func assertPresetListed(_ name: String) {
    openMenu()
    app.menuItems[name].assertExists("Preset “\(name)” not in the menu.")
    // Dismiss the menu so it doesn't block later interactions.
    app.typeKey(.escape, modifierFlags: [])
  }

  func assertPresetNotListed(_ name: String) {
    openMenu()
    app.menuItems[name].assertHidden("Preset “\(name)” should be gone from the menu.")
    app.typeKey(.escape, modifierFlags: [])
  }
}

/// Opens and inspects the Activity Log window (⇧⌘L).
struct ActivityLogScreen {
  let app: XCUIApplication

  @discardableResult
  func open() -> Self {
    app.focusWindow("Activity Log", openingWith: "l", modifiers: [.command, .shift])
    return self
  }

  func assertTableVisible() {
    app.descendant(id: "activity.table").assertExists("Activity Log table not shown.")
  }
}

/// Opens and inspects the About window.
struct AboutScreen {
  let app: XCUIApplication

  @discardableResult
  func open() -> Self {
    app.clickMenuItem("About SubTrack", in: "SubTrack")
    return self
  }

  func assertWindowVisible() {
    app.windows["About SubTrack"].assertExists("The About window never appeared.")
  }

  @discardableResult
  func openLicense() -> Self {
    app.descendant(id: "about.license")
      .assertExists("The About window has no License button.")
      .click()
    return self
  }

  func assertLicenseSheetVisible() {
    app.sheets.firstMatch.assertExists("The license sheet never appeared.")
  }
}
