import XCTest
import XCUITestKit

/// The inspector's Rules and Override tabs.
final class InspectorUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  func testRulesToggleEdits() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()

    inspector.setKeepUntagged(true)
    XCTAssertTrue(
      inspector.keepUntaggedToggle.isOn,
      "The rule toggle should reflect being turned on."
    )
    inspector.setKeepUntagged(false)
    XCTAssertFalse(
      inspector.keepUntaggedToggle.isOn,
      "The rule toggle should reflect being turned off."
    )
  }

  /**
   A file the queue hasn't finished inspecting still has to read as the file the
   user selected: the Override tab reports it as being inspected rather than
   claiming nothing is selected.

   The probe is stalled for far longer than the test needs rather than for a
   plausible probe duration: the seeded item starts being inspected as the app
   launches, so a window sized to the probe would be racing the launch itself.
   The other Override tests all run with instant probes, so the tab giving way
   to the tracks is covered by every one of them.
   */
  func testOverrideTabNamesTheFileItIsStillInspecting() {
    let app = SubTrack.launch(state: .oneReadyItem, probeDelayMilliseconds: 120_000)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()
    let inspector = window.showOverride()

    inspector.inspectingFile
      .assertExists("A file still being inspected should say so in the Override tab.")
    inspector.noFileSelected
      .assertHidden(
        "The Override tab shouldn’t report an empty selection while a file is selected."
      )
  }

  func testSkippingATrackChangesOutputTrackCount() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()
    let inspector = window.showOverride()

    XCTAssertTrue(window.outputTrackCount.wait())
    let before = window.outputTrackCountValue

    // Flip one subtitle track's include/skip; the planned output-track count must move.
    inspector.selectTrack(4)
    inspector.toggleInclude()

    XCTAssertTrue(
      window.outputTrackCount.waitFor(NSPredicate(format: "value != %@", before)),
      "Editing a track's include/skip should change the planned output tracks."
    )
  }

  func testCollidingOutputNamesBlockTheQueueUntilResolved() {
    let app = SubTrack.launch(state: .duplicateNames)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()

    inspector.nameFormatConflict
      .assertExists("Two sources sharing an output name should be reported on the format.")
    XCTAssertTrue(
      window.startAllButton.waitFor(NSPredicate(format: "isEnabled == false")),
      "Start All should be disabled while two files would be saved as the same name."
    )

    inspector.addNameToken("n")

    inspector.nameFormatConflict.assertHidden("Numbering the output should resolve the collision.")
    XCTAssertTrue(
      window.startAllButton.waitFor(NSPredicate(format: "isEnabled == true")),
      "Start All should come back once the names are distinct."
    )
  }

  func testIncludedTrackOffersConvertTarget() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()
    let inspector = window.showOverride()

    // The kept video track (stream 0) exposes a capability-driven "Convert to…" picker.
    inspector.selectTrack(0)
    inspector.convertPicker.assertExists("An included track should offer a convert-to picker.")
  }

  /**
   Handing the name back to the queue's format has to undo the rename, not
   just grey the field out.
   */
  func testDefaultNameRestoresTheQueuesFormat() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()
    let inspector = window.showOverride()
    inspector.setCustomName("Interstellar (trimmed)")
    XCTAssertTrue(
      window.destination.waitFor(
        NSPredicate(format: "value BEGINSWITH %@", "Interstellar (trimmed)")
      )
    )

    inspector.useDefaultName()

    XCTAssertTrue(
      window.destination.waitFor(
        NSPredicate(
          format: "value BEGINSWITH %@ AND NOT (value CONTAINS %@)",
          "Interstellar",
          "trimmed"
        )
      ),
      "Choosing the default name should put the queue’s format back."
    )
  }

  /**
   A file's own track edits are a departure from the queue's rules, so there
   has to be a way back: resetting drops them and the reset itself goes away
   with them.
   */
  func testResetReturnsAFileToTheQueuesRules() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()
    let inspector = window.showOverride()

    XCTAssertTrue(window.outputTrackCount.wait())
    let before = window.outputTrackCountValue
    inspector.selectTrack(4)
    inspector.toggleInclude()
    XCTAssertTrue(
      window.outputTrackCount.waitFor(NSPredicate(format: "value != %@", before)),
      "The override should have moved the planned track count."
    )

    inspector.resetToRules()

    XCTAssertTrue(
      window.outputTrackCount.waitFor(NSPredicate(format: "value == %@", before)),
      "Resetting should put the rules’ own plan back."
    )
    inspector.resetButton.assertHidden("A file back on the rules has nothing to reset.")
  }

  func testInspectorTabsSwitchFromTheSegmentedControl() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()

    window.showTabFromPicker("Override").noFileSelected
      .assertExists("The Override tab should be showing.")

    window.showTabFromPicker("Preview").previewNoFileSelected
      .assertExists("The Preview tab should be showing.")

    window.showTabFromPicker("Rules").keepUntaggedToggle
      .assertExists("The Rules tab should be showing.")
  }

  /**
   The Preview tab is a view of the output, not of the file: dropping a track
   has to take that track's position away and close the numbering up over it,
   or the positions would describe a file the run never writes.
   */
  func testPreviewRenumbersTheOutputAroundADroppedTrack() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()

    // The fixture's English audio (stream 1) and English subtitle (stream 3) are
    // both kept by the default rules, the subtitle behind the audio.
    let inspector = window.showPreview()
    let audioPosition = inspector.previewPosition(ofTrack: 1)
    XCTAssertNotEqual(audioPosition, "—", "The English audio should start out in the output.")
    XCTAssertNotEqual(
      inspector.previewPosition(ofTrack: 3),
      audioPosition,
      "The English subtitle should start out behind it."
    )

    window.showOverride().selectTrack(1)
    inspector.toggleInclude()
    window.showPreview()

    XCTAssertEqual(
      inspector.previewPosition(ofTrack: 1),
      "—",
      "A dropped track should still be listed, with no position in the output."
    )
    XCTAssertEqual(
      inspector.previewPosition(ofTrack: 3),
      audioPosition,
      "The tracks behind it should move up into the gap."
    )
  }

  func testToolbarButtonHidesAndShowsTheInspector() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()
    inspector.keepUntaggedToggle.assertExists("The inspector should start visible.")

    window.toggleInspectorFromToolbar()
    inspector.keepUntaggedToggle.assertHidden("The toolbar button should hide the inspector.")

    window.toggleInspectorFromToolbar()
    inspector.keepUntaggedToggle.assertExists("The toolbar button should bring it back.")
  }

  func testCustomNameRenamesOnlyThatFilesOutput() {
    let app = SubTrack.launch(state: .oneReadyItem)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.rowNamed("Interstellar.mkv").click()

    window.showOverride().setCustomName("Interstellar (trimmed)")

    XCTAssertTrue(
      window.destination.waitFor(
        NSPredicate(format: "value BEGINSWITH %@", "Interstellar (trimmed)")
      ),
      "Naming the file should rename the output it is queued to write."
    )
  }
}
