import XCTest
import XCUITestKit

/**
 The states that tell the user a run would go wrong: a source that has gone
 away, a plan the resolved build can't encode, a plan that would leave the
 output silent, and two files that would be written to one path.
 */
nonisolated final class WarningStatesUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
}

@MainActor
extension WarningStatesUITests {
  /**
   A deleted source is flagged on its row without the user doing anything — the
   file monitor notices it going away.

   Only the row is asserted. The Override tab's `sourceMissing` state needs an
   item that is *both* missing and unprobed, which happens when a queue is
   restored from persistence before it re-probes; a file deleted after it was
   added keeps the tracks already read from it, so that tab correctly still
   describes them.
   */
  func testMissingSourceIsReported() {
    let app = SubTrack.launch(state: .missingSource)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.missingStatus
      .assertExists("A source that has gone away should be flagged on its row.")
  }

  /**
   An item the selected build can't encode must be flagged before a run rather
   than failing in the middle of one, and must not be startable.
   */
  func testIncompatiblePlanIsFlaggedAndBlocksTheRun() {
    let app = SubTrack.launch(state: .incompatible)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.incompatibleStatus
      .assertExists("A plan needing an unavailable encoder should be flagged.")
    XCTAssertTrue(
      window.startAllButton.waitFor(NSPredicate(format: "isEnabled == false")),
      "An incompatible item isn’t startable."
    )
  }

  /// A plan that keeps none of the source's audio warns on the row.
  func testSilentOutputIsWarnedAbout() {
    let app = SubTrack.launch(state: .audioLoss)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.audioWarning
      .assertExists("Dropping every audio track should warn on the row.")
  }

  /**
   A collision is reported where it is caused: the Rules tab covers the format
   that caused it, and the Override tab reports it against each file caught up
   in it.
   */
  func testCollidingNameIsReportedOnTheFile() {
    let app = SubTrack.launch(state: .duplicateNames)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Show.mkv").click()

    window.showOverride().nameConflict
      .assertExists("A file whose output collides should say so in its own tab.")
  }
}
