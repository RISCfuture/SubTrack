import XCTest
import XCUITestKit

/// Destination, multi-queue workspace, and removing items.
final class QueueManagementUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  func testChangeDestination() {
    let app = SubTrack.launch(state: .oneReadyItem)
    MainWindowScreen(app: app).waitUntilLoaded()

    app.buttons["destination.change"].click()

    // The destination bar now shows the chosen fixture folder's path.
    XCTAssertTrue(
      app.descendant(id: "destination.path").waitFor(
        NSPredicate(format: "value CONTAINS %@", "UITestFixtures/destination")
      ),
      "The destination bar should show the chosen folder."
    )
  }

  func testCreateAndDeleteQueue() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()
    let sidebar = SidebarScreen(app: app).ensureVisible()
    sidebar.assertQueueExists(named: "Queue 1")

    // New Queue (⌘N) creates and selects "Queue 2".
    sidebar.newQueue()
    sidebar.assertQueueExists(named: "Queue 2")
    XCTAssertEqual(sidebar.queueRowCount, 2)

    // Delete the selected (empty) queue; an empty queue deletes without a prompt.
    sidebar.deleteSelectedQueue()
    sidebar.assertQueueGone(named: "Queue 2")
    XCTAssertEqual(sidebar.queueRowCount, 1)
  }

  func testRemoveSelectedItem() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()

    app.typeKey(.delete, modifierFlags: [])

    window.assertEmptyStateVisible()
  }

  func testClearCompleted() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.startAll()
    window.assertItemFinished()

    app.clickMenuItem("Clear Completed", in: "Queue")

    window.assertEmptyStateVisible()
  }

  // MARK: - The workspace

  /**
   Each queue holds its own items, so selecting one in the sidebar has to swap
   what the window is showing. Only "Movies" is seeded with a file, which is
   what makes the switch observable.
   */
  func testSelectingAQueueSwapsItsContents() {
    let app = SubTrack.launch(state: .multiQueue)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let sidebar = SidebarScreen(app: app).ensureVisible()
    window.assertEmptyStateVisible()

    sidebar.selectQueue(named: "Movies")
    window.assertRow(named: "Interstellar.mkv")

    sidebar.selectQueue(named: "TV Shows")
    window.assertEmptyStateVisible()
  }

  func testNewQueueFromSidebarButton() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()
    let sidebar = SidebarScreen(app: app).ensureVisible()

    sidebar.newQueueFromButton()

    sidebar.assertQueueExists(named: "Queue 2")
    XCTAssertEqual(sidebar.queueRowCount, 2)
  }

  // Renaming a queue is not UI-tested: the inline rename `TextField` in a `List`
  // row does not surface to the accessibility tree (`sidebar.renameField` is
  // never found), so the flow can't be driven from out of process. The binding
  // behind it is thin and `Workspace.renameQueue` is covered by unit tests.

  /**
   Deleting a queue that still has work in it would cancel that work, so it
   asks first — unlike the empty queue in `testCreateAndDeleteQueue`, which
   goes without a prompt.
   */
  func testDeletingAQueueWithWorkAsksFirst() {
    let app = SubTrack.launch(state: .oneReadyItem)
    MainWindowScreen(app: app).waitUntilLoaded()
    let sidebar = SidebarScreen(app: app).ensureVisible()
    // A second queue, so deleting the seeded one leaves something behind: the
    // workspace always holds at least one queue and would otherwise replace it
    // with a fresh "Queue 1", which reads exactly like a deletion that failed.
    sidebar.newQueue()
    sidebar.selectQueue(named: "Queue 1")

    sidebar.deleteSelectedQueue()

    sidebar.assertDeletionConfirmationShown()
    sidebar.confirmQueueDeletion()
    sidebar.assertQueueGone(named: "Queue 1")
    sidebar.assertQueueExists(named: "Queue 2")
  }

  // MARK: - Row actions

  func testRowMenuStartsAnItem() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.rowMenu("Start", on: "Interstellar.mkv")

    window.assertItemFinished()
  }

  func testRowMenuRemovesAnItem() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.rowMenu("Remove", on: "Interstellar.mkv")

    window.assertEmptyStateVisible()
  }

  /**
   A re-scan reads the file's tracks again, so the item passes back through
   being inspected. The probe is stalled far longer than the test needs so the
   transient state can't be raced.
   */
  func testRowMenuRescansAnItem() {
    let app = SubTrack.launch(state: .oneReadyItem, probeDelayMilliseconds: 120_000)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.rowMenu("Re-scan", on: "Interstellar.mkv")

    app.descendant(id: "queue.status.probing")
      .assertExists("A re-scanned item should report being inspected.")
  }

  func testCancelAllViaKeyboardCommand() {
    let app = SubTrack.launch(state: .oneReadyItem, stepDelayMilliseconds: 1500)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.startAll()

    window.cancelAllViaKeyboard()

    window.assertNotRunning()
    XCTAssertFalse(window.doneStatus.exists, "A cancelled item must not report as finished.")
  }

  func testStartSelectedViaKeyboardCommand() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()

    window.startSelectedViaKeyboard()

    window.assertItemFinished()
  }

  /**
   A folder large enough that minting each row's bookmarks takes real time, so
   the ingest is still running when the sheet is looked for. Cancelling it
   stops the ingest rather than merely hiding the sheet.

   The count is deliberately far past what the assertions need: at 1,200 files
   the ingest finished between finding the sheet and clicking its button.
   */
  func testIngestSheetReportsAndCancelsAFolderAdd() {
    let app = SubTrack.launch(state: .empty, largeFolderSize: 6000)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.addFolder()

    window.ingestSheet.assertExists("Adding a large folder should report its progress.")
    // The sheet's own button, not `ingest.cancel`: an identifier on a Button
    // inside a SwiftUI sheet doesn't reach the accessibility tree.
    app.sheets.firstMatch.buttons.firstMatch
      .assertExists("The ingest sheet has no Cancel button.")
      .click()

    window.ingestSheet.assertHidden("Cancelling the ingest should dismiss its sheet.")
  }
}
