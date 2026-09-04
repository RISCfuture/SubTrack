import XCTest

/// Adding sources to the queue and running them through the stubbed engine.
nonisolated final class AddAndRunUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
}

@MainActor
extension AddAndRunUITests {
  func testAddFilesFromToolbar() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.assertEmptyStateVisible()

    window.addFiles()

    window.assertRow(named: "Interstellar.mkv")
    window.assertRow(named: "Arrival.mkv")
    XCTAssertTrue(window.startAllButton.isEnabled, "Start All should enable once files are queued.")
  }

  func testAddFilesFromEmptyStateButton() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.addFilesFromEmptyState()

    window.assertRow(named: "Interstellar.mkv")
  }

  func testAddFolder() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.addFolder()

    window.assertRow(named: "Dune.mkv")
    window.assertRow(named: "Sicario.mkv")
  }

  func testRunToCompletion() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.startAll()

    window.assertItemFinished()
    XCTAssertFalse(
      window.outputTrackCountValue.isEmpty,
      "A finished item should report its output track count."
    )
  }

  func testCancelRun() {
    // A long step delay keeps the stubbed run in flight so the cancel lands before
    // it can finish, letting us tell a cancelled item from a completed one.
    let app = SubTrack.launch(state: .oneReadyItem, stepDelayMilliseconds: 1500)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.startAll()
    window.cancelAll()

    window.assertNotRunning()
    XCTAssertFalse(window.doneStatus.exists, "A cancelled item must not report as finished.")
    XCTAssertTrue(window.startAllButton.isEnabled, "A cancelled item is startable again.")
  }

  func testFailedRunSurfacesError() {
    let app = SubTrack.launch(state: .oneReadyItem, engine: .fail)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.startAll()

    window.assertItemFailed()
  }
}
