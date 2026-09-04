import XCTest
import XCUITestKit

/**
 The Rules tab's list editors — the languages kept, in priority order. The
 preferred-codec rows are the same ``StringListEditor`` over a different list,
 so they are covered by these rather than repeated three more times.
 */
nonisolated final class RulesEditingUITests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
}

@MainActor
extension RulesEditingUITests {
  func testAddingAndRemovingALanguage() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()

    inspector.openLanguages().addLanguage("jpn")

    inspector.assertLanguageRow("jpn")
    XCTAssertTrue(
      inspector.languagesSummary.waitFor(NSPredicate(format: "value CONTAINS %@", "Japanese")),
      "A recognized code should be summarized by its language name."
    )

    inspector.removeLanguage("jpn")

    inspector.assertNoLanguageRow("jpn")
    XCTAssertFalse(
      inspector.languagesSummaryValue.contains("Japanese"),
      "A removed language should leave the summary."
    )
  }

  /// An unrecognized code is kept — it just can't be resolved to a name.
  func testUnknownLanguageCodeIsFlagged() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()

    inspector.openLanguages().addLanguage("zzz")

    inspector.assertLanguageRow("zzz")
    app.images["Unrecognized code"].firstMatch
      .assertExists("An unrecognized code should be flagged as such.")
  }

  /**
   There are hundreds of codes, so the `+` menu opens a searchable browser
   rather than listing them; choosing there has to land in the list.
   */
  func testBrowsingForALanguageAddsIt() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()

    inspector.openLanguages().browseForLanguage("swe", searching: "Swedish")

    XCTAssertTrue(
      inspector.languagesSummary.waitFor(NSPredicate(format: "value CONTAINS %@", "Swedish")),
      "A language chosen in the browser should join the kept languages."
    )
  }
}
