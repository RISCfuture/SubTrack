import XCTest
import XCUITestKit

/// The preset menu and the Settings tab that manages what it lists.
final class PresetsUITests: XCTestCase {

  /// The starter preset whose rules differ from the default in a visible toggle.
  private let keepUntaggedPreset = "Blu-ray Rip — Keep Untagged Tracks"

  override func setUp() { continueAfterFailure = false }

  func testSaveCurrentAsPresetListsIt() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let presets = PresetsScreen(app: app)
    presets.saveCurrentAsPreset(named: "Everything But French")

    presets.assertPresetListed("Everything But French")
  }

  /**
   Applying a preset has to move the queue's rules, not just tick a menu: the
   chosen starter is the one that keeps untagged tracks, so the Rules tab's
   toggle is what proves it landed.
   */
  func testApplyingAPresetChangesTheRules() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let inspector = window.showRules()
    inspector.setKeepUntagged(false)

    PresetsScreen(app: app).apply(keepUntaggedPreset)

    XCTAssertTrue(
      inspector.keepUntaggedToggle.waitFor(NSPredicate(format: "value == 1")),
      "Applying the keep-untagged preset should turn its rule on."
    )
  }

  /**
   Which preset is "active" follows what the rules *are*, so editing away from
   an applied preset must stop the menu claiming it.
   */
  func testEditingRulesLeavesThePresetBehind() {
    let app = SubTrack.launch(state: .empty)
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    let presets = PresetsScreen(app: app)
    presets.apply(keepUntaggedPreset)
    presets.assertActivePreset(keepUntaggedPreset)

    let inspector = window.showRules()
    inspector.setKeepUntagged(false)

    presets.assertNotActivePreset(keepUntaggedPreset)
  }

  // MARK: - Settings ▸ Presets

  func testRenamingAPresetRenamesItInTheMenu() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("Presets")
    PresetsSettingsScreen(app: app)
      .select(keepUntaggedPreset)
      .rename(to: "Keep Everything")

    settings.close()
    PresetsScreen(app: app).assertPresetListed("Keep Everything")
  }

  func testEditingAPresetsRulesFromSettings() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("Presets")
    let presets = PresetsSettingsScreen(app: app).select(keepUntaggedPreset)

    // The preset editor hosts the same rules form as the inspector, so the
    // toggle is edited the same way and written straight through to the store.
    let toggle = app.descendant(id: "rules.keepUntagged")
      .assertExists("The preset editor has no keep-untagged toggle.")
    XCTAssertTrue(toggle.isOn, "The starter preset should keep untagged tracks.")
    toggle.click()

    XCTAssertFalse(toggle.isOn, "Editing a preset’s rule should stick.")
    presets.assertListed(keepUntaggedPreset)
  }

  func testDeletingAPresetRemovesItFromTheMenu() {
    let app = SubTrack.launch(state: .empty)
    MainWindowScreen(app: app).waitUntilLoaded()

    let settings = SettingsScreen(app: app).open()
    settings.showTab("Presets")
    PresetsSettingsScreen(app: app)
      .select(keepUntaggedPreset)
      .deleteSelected()
      .assertNotListed(keepUntaggedPreset)

    settings.close()
    PresetsScreen(app: app).assertPresetNotListed(keepUntaggedPreset)
  }
}
