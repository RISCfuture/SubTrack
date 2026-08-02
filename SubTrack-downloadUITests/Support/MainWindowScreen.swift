import XCTest
import XCUITestKit

/**
 Drives SubTrack's main queue window — the toolbar, destination bar, queue
 table, and status bar. Actions return a screen object so a test reads as a
 sequence of user intents; `assert…` helpers keep *how* a fact is checked here
 while the test keeps *what* it is proving.
 */
struct MainWindowScreen {
  /// Where on the Add control its menu's disclosure arrow sits.
  private static let addMenuArrow = CGVector(dx: 0.88, dy: 0.5)

  let app: XCUIApplication

  // MARK: - Element accessors

  var startAllButton: XCUIElement { app.buttons["toolbar.startAll"] }
  var cancelButton: XCUIElement { app.buttons["toolbar.cancel"] }
  var toggleInspectorButton: XCUIElement { app.buttons["toolbar.toggleInspector"] }
  var emptyState: XCUIElement { app.descendant(id: "queue.emptyState") }
  var statusSummary: XCUIElement { app.descendant(id: "status.summary") }
  var overallProgress: XCUIElement { app.descendant(id: "status.overallProgress") }
  var doneStatus: XCUIElement { app.descendant(id: "queue.status.done") }
  var failedStatus: XCUIElement { app.descendant(id: "queue.status.failed") }
  var missingStatus: XCUIElement { app.descendant(id: "queue.status.missing") }
  var incompatibleStatus: XCUIElement { app.descendant(id: "queue.status.incompatible") }
  var audioWarning: XCUIElement { app.descendant(id: "queue.cell.audioWarning") }
  var outputSize: XCUIElement { app.staticTexts["queue.cell.outputSize"] }
  var ingestSheet: XCUIElement { app.descendant(id: "ingest.sheet") }
  var inspectorModePicker: XCUIElement { app.descendant(id: "inspector.mode") }

  /// The trailing inspector as one element, so a screenshot can frame it alone.
  var inspectorPane: XCUIElement { app.descendant(id: "inspector.pane") }

  var summaryValue: String { (statusSummary.value as? String) ?? "" }

  /**
   The output-track count for the single-item queue. Reading a specific row's
   cell is unambiguous only with one row, which the `oneReadyItem` state gives.
   */
  var outputTrackCount: XCUIElement { app.staticTexts["queue.cell.outputTracks"] }
  var outputTrackCountValue: String { (outputTrackCount.value as? String) ?? "" }
  var destination: XCUIElement { app.staticTexts["queue.cell.destination"] }

  func rowNamed(_ name: String) -> XCUIElement {
    app.staticTexts.matching(
      NSPredicate(format: "identifier == %@ AND value == %@", "queue.cell.name", name)
    ).firstMatch
  }

  /// One named editor within a form, so a screenshot can frame just that part of it.
  func editor(_ identifier: String) -> XCUIElement { app.descendant(id: identifier) }

  // MARK: - Landing

  @discardableResult
  func waitUntilLoaded() -> Self {
    XCTAssertTrue(
      app.descendant(id: "queue.table").wait() || app.descendant(id: "queue.emptyState").wait(),
      "The main queue window never appeared."
    )
    return self
  }

  // MARK: - Adding sources

  /**
   Adds the fixture movies through the File ▸ Add Files… command (⌘O), which the
   harness resolves to fixtures instead of an open panel.
   */
  @discardableResult
  func addFiles() -> Self {
    app.typeKey("o", modifierFlags: .command)
    return self
  }

  /// Adds the fixture folder through File ▸ Add Folder… (⇧⌘O).
  @discardableResult
  func addFolder() -> Self {
    app.typeKey("o", modifierFlags: [.command, .shift])
    return self
  }

  /**
   Adds the fixture movies by clicking the empty state's own button.

   The button answers to `queue.emptyState`, not to the `queue.emptyState.add`
   the source puts on it: `ContentUnavailableView` stamps its own identifier
   onto every element it emits, overwriting the ones its content carries. Asking
   for the *button* with that identifier is what separates it from the two
   static texts sharing it.
   */
  @discardableResult
  func addFilesFromEmptyState() -> Self {
    app.buttons["queue.emptyState"]
      .assertExists("The empty state's Add button never appeared.")
      .click()
    return self
  }

  /**
   Opens the toolbar's Add menu, which is the only place both ways of adding
   sources are offered together.

   Clicked on its disclosure arrow rather than anywhere on the control: Add is
   a split button whose primary action adds files outright, so a centred click
   ingests the fixtures instead of showing the menu.
   */
  @discardableResult
  func openAddMenu() -> Self {
    app.descendant(id: "toolbar.add")
      .assertExists("The toolbar’s Add control is missing.")
      .coordinate(withNormalizedOffset: Self.addMenuArrow)
      .click()
    app.openMenu()
    return self
  }

  // MARK: - Running

  @discardableResult
  func startAll() -> Self {
    let button = startAllButton.assertExists("Start All never appeared.")
    XCTAssertTrue(button.isEnabled, "Start All should be enabled once an item is ready.")
    button.click()
    return self
  }

  @discardableResult
  func cancelAll() -> Self {
    cancelButton.click()
    return self
  }

  /// Cancels the run through the Queue menu's ⌘. shortcut rather than the toolbar.
  @discardableResult
  func cancelAllViaKeyboard() -> Self {
    app.typeKey(".", modifierFlags: .command)
    return self
  }

  /// Starts only the selected rows through the Queue menu's ⌘⏎ shortcut.
  @discardableResult
  func startSelectedViaKeyboard() -> Self {
    app.typeKey(.return, modifierFlags: .command)
    return self
  }

  // MARK: - Row actions

  /**
   Opens a row's context menu and clicks `item`. `Table` routes a right-click
   to the whole selection when the row is in it, so this is how every
   selection-wide row action is driven.
   */
  @discardableResult
  func rowMenu(_ item: String, on name: String) -> Self {
    rowNamed(name).assertExists("Expected a queue row for “\(name)”.").rightClick()
    app.menuItems[item].firstMatch
      .assertExists("“\(item)” isn’t offered by the row menu.")
      .click()
    return self
  }

  // MARK: - Inspector

  @discardableResult
  func showRules() -> InspectorScreen { switchInspector(key: "1") }
  @discardableResult
  func showOverride() -> InspectorScreen { switchInspector(key: "2") }

  @discardableResult
  func toggleInspector() -> Self {
    switchInspector(key: "i")
    return self
  }

  /// Hides or shows the inspector with the toolbar button rather than ⌘⌥I.
  @discardableResult
  func toggleInspectorFromToolbar() -> Self {
    toggleInspectorButton.assertExists("The inspector toolbar button is missing.").click()
    return self
  }

  /**
   Switches inspector tabs by clicking the segmented control. The Picker's own
   identifier matches several elements, so the tab is chosen by its label.
   */
  @discardableResult
  func showTabFromPicker(_ name: String) -> InspectorScreen {
    inspectorModePicker.firstMatch
      .assertExists("The inspector mode picker isn’t shown.")
      .radioButtons[name]
      .assertExists("The “\(name)” inspector tab isn’t offered.")
      .click()
    return InspectorScreen(app: app)
  }

  @discardableResult
  private func switchInspector(key: String) -> InspectorScreen {
    app.typeKey(key, modifierFlags: [.command, .option])
    return InspectorScreen(app: app)
  }

  // MARK: - Assertions

  func assertEmptyStateVisible() {
    emptyState.assertExists("Expected the empty-queue state.")
    XCTAssertFalse(startAllButton.isEnabled, "Start All should be disabled with an empty queue.")
  }

  func assertRow(named name: String) {
    rowNamed(name).assertExists("Expected a queue row for “\(name)”.")
  }

  func assertItemFinished() {
    doneStatus.assertExists("Expected an item to finish.", timeout: ScaledTimeouts.slowElement)
  }

  func assertItemFailed() {
    failedStatus.assertExists("Expected an item to fail.", timeout: ScaledTimeouts.slowElement)
  }

  func assertNotRunning() {
    XCTAssertTrue(
      cancelButton.waitFor(NSPredicate(format: "isEnabled == false")),
      "Expected the run to stop (Cancel becomes disabled)."
    )
  }

  func assertRowGone(named name: String) {
    rowNamed(name).assertHidden("Queue row “\(name)” should be gone.")
  }

  /// Waits for the status bar to report `count` items.
  func assertItemCount(_ count: Int) {
    XCTAssertTrue(
      statusSummary.waitFor(NSPredicate(format: "value BEGINSWITH %@", "\(count) items")),
      "Expected the status bar to report \(count) items, got “\(summaryValue)”."
    )
  }
}
