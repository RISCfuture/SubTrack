import XCTest
import XCUITestKit

/**
 Drives the workspace sidebar: creating, selecting, and deleting queues. Queue
 names double as their locators — they are data the test seeds, not localized
 chrome.
 */
struct SidebarScreen {
  let app: XCUIApplication

  var queueRowCount: Int {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.queueRow.")
    ).count
  }

  /**
   Reveals the workspace sidebar, which `NavigationSplitView` collapses at this
   window size. Idempotent: only clicks "Show Sidebar" when the list is hidden.
   */
  @discardableResult
  func ensureVisible() -> Self {
    if !app.descendant(id: "sidebar.queueList").wait(scaledSeconds: 2) {
      app.buttons["Show Sidebar"].click()
      app.descendant(id: "sidebar.queueList").assertExists("The sidebar never appeared.")
    }
    return self
  }

  @discardableResult
  func newQueue() -> Self {
    app.typeKey("n", modifierFlags: .command)
    return self
  }

  /// Creates a queue with the sidebar's own bottom-bar button rather than ⌘N.
  @discardableResult
  func newQueueFromButton() -> Self {
    app.descendant(id: "sidebar.newQueue")
      .assertExists("The sidebar's New Queue button is missing.")
      .click()
    return self
  }

  @discardableResult
  func selectQueue(named name: String) -> Self {
    row(named: name).assertExists("Expected a queue named “\(name)”.").click()
    return self
  }

  /// Confirms the dialog shown when deleting a queue that still has work in it.
  @discardableResult
  func confirmQueueDeletion() -> Self {
    app.sheets.firstMatch.buttons["Delete Queue"]
      .assertExists("The delete-queue confirmation never appeared.")
      .click()
    return self
  }

  func assertDeletionConfirmationShown() {
    app.sheets.firstMatch
      .assertExists("Deleting a queue with unfinished work should ask first.")
  }

  /**
   Deletes the selected queue through File ▸ Delete Queue. Only used on queues
   with no unfinished work, which delete without a confirmation dialog.
   */
  @discardableResult
  func deleteSelectedQueue() -> Self {
    app.clickMenuItem("Delete Queue", in: "File")
    return self
  }

  func row(named name: String) -> XCUIElement {
    app.staticText(value: name)
  }

  // MARK: - Assertions

  func assertQueueExists(named name: String) {
    row(named: name).assertExists("Expected a queue named “\(name)”.")
  }

  func assertQueueGone(named name: String) {
    row(named: name).assertHidden("Queue “\(name)” should be gone.")
  }
}
