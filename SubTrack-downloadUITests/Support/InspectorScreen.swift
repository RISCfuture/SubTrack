import XCTest
import XCUITestKit

/**
 Drives the trailing inspector — the Rules and Override tabs. Reached through
 the main window's `showRules()` / `showOverride()` (⌘⌥1 / ⌘⌥2).

 The Override tab describes one track at a time, so anything track-specific
 goes through `selectTrack(_:)` first.
 */
struct InspectorScreen {
  /// One scroll-wheel push, in points; negative moves the form further down.
  private static let revealScrollStep = -80.0

  /// How many pushes ``reveal(_:)`` gives the form before it gives up.
  private static let revealScrollLimit = 20

  let app: XCUIApplication

  var keepUntaggedToggle: XCUIElement { app.descendant(id: "rules.keepUntagged") }
  var nameFormatField: XCUIElement { app.descendant(id: "rules.nameFormat") }

  /**
   The warning shown when the output-name format would have two files collide
   or overwrite their own source.
   */
  var nameFormatConflict: XCUIElement { app.descendant(id: "rules.nameFormatConflict") }

  var trackPicker: XCUIElement { app.descendant(id: "override.trackPicker") }

  /**
   The Override tab's stand-ins for a file it can't describe yet: nothing (or
   too much) selected, and a file selected but not yet inspected.
   */
  var noFileSelected: XCUIElement { app.descendant(id: "override.noFileSelected") }
  var inspectingFile: XCUIElement { app.descendant(id: "override.inspecting") }

  var includeToggle: XCUIElement { app.descendant(id: "override.include") }
  var convertPicker: XCUIElement { app.descendant(id: "override.convert") }
  var customNameField: XCUIElement { app.descendant(id: "override.customName") }
  var fileNameMode: XCUIElement { app.descendant(id: "override.fileNameMode") }

  /// Returns the file to the queue's rules, shown only once it has an override.
  var resetButton: XCUIElement { app.descendant(id: "override.reset") }

  /// The collision warning as reported against this one file.
  var nameConflict: XCUIElement { app.descendant(id: "override.nameConflict") }

  /// The Preview tab's table of the output's tracks, and its kept-of-total line.
  var previewTable: XCUIElement { app.descendant(id: "preview.table") }
  var previewSummary: XCUIElement { app.descendant(id: "preview.summary") }

  /// The Preview tab's stand-in when the selection isn't one inspectable file.
  var previewNoFileSelected: XCUIElement { app.descendant(id: "preview.noFileSelected") }

  /// The languages-to-keep summary in the Rules tab.
  var languagesSummary: XCUIElement { app.descendant(id: "rules.languages") }
  var languagesSummaryValue: String { (languagesSummary.value as? String) ?? "" }

  /**
   Where the track at `streamIndex` lands in the output, as the Preview tab
   shows it: a position, or an em dash for a track the run drops. Addressed by
   source stream index, which is stable however the plan reorders the rows.
   */
  func previewPosition(ofTrack streamIndex: Int) -> String {
    let cell = app.staticTexts["preview.number.\(streamIndex)"]
      .assertExists("Track \(streamIndex) has no row in the preview table.")
    return (cell.value as? String) ?? ""
  }

  /**
   Scrolls the inspector's form until the control identified by `identifier` is
   on screen. The tabs are taller than the pane, so anything below the section
   the tab opens on has to be brought into view before it can be driven — or
   photographed.

   The scroll is aimed at the pane rather than at a scroll view found by type:
   the wheel event lands wherever the pointer is put, and the form underneath
   handles it whatever AppKit calls it.
   */
  @discardableResult
  func reveal(_ identifier: String) -> Self {
    let pane = app.descendant(id: "inspector.pane")
      .assertExists("The inspector pane isn’t shown.")
    let target = app.descendant(id: identifier)
    for _ in 0..<Self.revealScrollLimit {
      if target.exists, target.isHittable { return self }
      pane.scroll(byDeltaX: 0, deltaY: Self.revealScrollStep)
    }
    XCTAssertTrue(
      target.exists && target.isHittable,
      "“\(identifier)” never scrolled into view."
    )
    return self
  }

  /// Adds a token to the end of the output-name format by clicking its chip.
  @discardableResult
  func addNameToken(_ token: String) -> Self {
    app.descendant(id: "rules.nameToken.\(token)")
      .assertExists("The “\(token)” name token isn’t offered.")
      .click()
    return self
  }

  /**
   Points the Override tab at one of the file's tracks, so the detail and
   override controls below describe it. Rows are titled by stream index, which
   is stable however the plan reorders them.
   */
  @discardableResult
  func selectTrack(_ index: Int) -> Self {
    trackPicker.assertExists("The track picker isn’t shown.").click()
    app.menuItems
      .matching(NSPredicate(format: "title BEGINSWITH %@", "\(index) · "))
      .firstMatch
      .assertExists("Track \(index) isn’t offered by the picker.")
      .click()
    return self
  }

  /**
   Toggles the selected track's include/skip control and returns whether it was
   on beforehand, so a test can assert the plan moved in the matching direction.
   */
  @discardableResult
  func toggleInclude() -> Bool {
    let toggle = includeToggle.assertExists("The track include toggle isn’t shown.")
    let wasOn = toggle.isOn
    toggle.click()
    return wasOn
  }

  /**
   Takes the selected file's name over from the queue's format and types
   `name` into the field.
   */
  @discardableResult
  func setCustomName(_ name: String) -> Self {
    // By identifier, not label: SwiftUI prefixes the Picker's own label onto each
    // option, so this radio button's label is "File name, Use custom name:".
    app.descendant(id: "override.useCustomName")
      .assertExists("The custom-name option isn’t offered.")
      .click()
    let field = customNameField.assertExists("The custom-name field isn’t shown.")
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(name)
    return self
  }

  @discardableResult
  func setKeepUntagged(_ on: Bool) -> Self {
    let toggle = keepUntaggedToggle.assertExists("Keep-untagged toggle not found.")
    if toggle.isOn != on { toggle.click() }
    return self
  }

  /// Hands the file's name back to the queue's format.
  @discardableResult
  func useDefaultName() -> Self {
    app.descendant(id: "override.useDefaultName")
      .assertExists("The default-name option isn’t offered.")
      .click()
    return self
  }

  /// Drops this file's own track overrides, returning it to the queue's rules.
  @discardableResult
  func resetToRules() -> Self {
    resetButton.assertExists("The reset-to-rules button isn’t shown.").click()
    return self
  }

  // MARK: - Languages

  /**
   Opens the languages list editor from the Rules tab. Its rows and `+` menu
   are addressed as `rules.languages.…`, so everything below assumes it is open.
   */
  @discardableResult
  func openLanguages() -> Self {
    app.descendant(id: "rules.languages.edit")
      .assertExists("The languages Edit button isn’t shown.")
      .click()
    return self
  }

  /// Appends `code` through the editor's `+` menu, typing it as an "Other" entry.
  @discardableResult
  func addLanguage(_ code: String) -> Self {
    app.descendant(id: "rules.languages.add")
      .assertExists("The languages + menu isn’t shown.")
      .click()
    app.menuItems["Other"].firstMatch.assertExists("The + menu has no “Other” item.").click()
    app.typeText(code)
    return self
  }

  @discardableResult
  func removeLanguage(_ code: String) -> Self {
    app.descendant(id: "rules.languages.remove.\(code)")
      .assertExists("No “\(code)” row to remove.")
      .click()
    return self
  }

  /**
   Opens the searchable browser from the editor's `+` menu and toggles the
   language whose code is `code`, searching by `query` first so the row is in
   view.
   */
  @discardableResult
  func browseForLanguage(_ code: String, searching query: String) -> Self {
    app.descendant(id: "rules.languages.add")
      .assertExists("The languages + menu isn’t shown.")
      .click()
    app.menuItems["Browse Languages…"].firstMatch
      .assertExists("The + menu has no language browser.")
      .click()
    let search = app.descendant(id: "language.search")
      .assertExists("The language browser never appeared.")
    search.click()
    search.typeText(query)
    app.descendant(id: "language.row.\(code)")
      .assertExists("“\(code)” isn’t listed for “\(query)”.")
      .click()
    return self
  }

  func assertLanguageRow(_ code: String) {
    app.descendant(id: "rules.languages.row.\(code)")
      .assertExists("Expected a “\(code)” row in the languages editor.")
  }

  func assertNoLanguageRow(_ code: String) {
    app.descendant(id: "rules.languages.row.\(code)")
      .assertHidden("The “\(code)” row should be gone.")
  }
}
