import XCTest
import XCUITestKit

/**
 Smoke test proving the UI-test harness pipeline: the app launches in stubbed
 UI-test mode and lands on the empty-queue state.
 */
nonisolated final class SubTrackSmokeUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }
}

@MainActor
extension SubTrackSmokeUITests {
  func testLaunchShowsEmptyState() {
    let app = SubTrack.launch()
    app.descendant(id: "queue.emptyState")
      .assertExists("The empty-queue state should be visible on a fresh launch.")
  }
}
