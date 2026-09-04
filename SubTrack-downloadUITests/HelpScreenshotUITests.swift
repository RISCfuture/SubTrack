import XCTest
import XCUITestKit

/**
 Captures the Help book's images from the running app, so they are a build
 product of the thing they document rather than hand-made pictures that rot.

 Not part of any ordinary test run: `fastlane help_screenshots` names this class
 with `-only-testing:`, and CI skips it with `-skip-testing:`. The precondition
 below is the defence that survives an edit to either — a machine whose display,
 accent colour, or accessibility settings would change what is drawn skips the
 whole class rather than quietly shipping twenty-four different images.

 Each article's shot is taken twice, once per appearance, because the Help book's
 stylesheet adapts to both and a light-only image is the one element on a dark
 page that doesn't.
 */
nonisolated final class HelpScreenshotUITests: XCTestCase {
  /// The window the queue articles are shot in: wide enough for the sidebar, the table, and the inspector.
  private static let queueWindowSize = CGSize(width: 1280, height: 860)

  /// The window the Settings articles are shot in — it is only ever the backdrop.
  private static let settingsWindowSize = CGSize(width: 1000, height: 620)

  /// The window the troubleshooting article is shot in: six rows and their statuses.
  private static let problemsWindowSize = CGSize(width: 1180, height: 620)

  /// Main-actor isolated because the capture preconditions read `NSScreen` and `NSWorkspace`.
  @MainActor
  override func setUp() async throws {
    continueAfterFailure = false
    try XCTSkipUnless(
      ScreenshotPreconditions.machineCanCapture,
      "Help screenshots need a capture-ready Mac: \(ScreenshotPreconditions.unmetRequirement)."
    )
  }
}

@MainActor
extension HelpScreenshotUITests {
  // MARK: - Queue and rules articles

  func testCapturesQueueArticlesInLightAppearance() { captureQueueArticles(in: .light) }
  func testCapturesQueueArticlesInDarkAppearance() { captureQueueArticles(in: .dark) }

  /**
   The seven shots the queue, rules, and preset articles use, taken in one
   launch: every one of them is of the same seeded queue, and relaunching per
   image would triple what the pass costs for nothing.
   */
  private func captureQueueArticles(in appearance: SubTrack.Appearance) {
    let app = SubTrack.launch(
      state: .helpQueue,
      appearance: appearance,
      windowSize: Self.queueWindowSize
    )
    let mainWindow = app.windows["SubTrack"]
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    SidebarScreen(app: app).ensureVisible().selectQueue(named: "Blu-ray Rips")
    window.showRules()
    parkPointer(in: app)
    capture(slug("main-window", in: appearance), of: mainWindow)

    // Hiding the inspector gives the table the whole window, which is what the
    // article about watching a run is describing.
    window.toggleInspectorFromToolbar()
    parkPointer(in: app)
    capture(slug("queue-running", in: appearance), of: mainWindow)

    let inspector = window.toggleInspectorFromToolbar().showRules()
    captureRulesArticles(inspector, of: window, in: appearance)
    capturePresetMenu(app, of: mainWindow, in: appearance)
    captureTrackOverride(app, of: window, in: appearance)
    capturePreviewTab(app, of: window, in: appearance)
  }

  /**
   The three rules shots, each framing only what its article is about. Every
   section of the inspector fits in one pane-height capture, so three shots of
   the pane would be three copies of the same picture.
   */
  private func captureRulesArticles(
    _ inspector: InspectorScreen,
    of window: MainWindowScreen,
    in appearance: SubTrack.Appearance
  ) {
    // The language editor is captured as itself. It is a popover — its own
    // window, which macOS opens wherever there is room for it, and here that is
    // past the main window's trailing edge. Since a capture is a crop of the
    // composited desktop at the captured element's frame, framing anything the
    // popover overhangs would cut it off rather than show it.
    inspector.openLanguages()
    parkPointer(in: window.app)
    capture(
      slug("rules-languages", in: appearance),
      of: window.app.popovers.firstMatch.assertExists("The language editor never opened.")
    )
    dismissTransientUI(in: window.app)

    // Of the whole pane: a `Form`'s sections are not addressable as single
    // elements — SwiftUI stamps a section identifier onto each row it emits
    // rather than emitting one element spanning them — so the preferred codecs
    // and the transcode targets they fall back to can only be shown together
    // by showing the pane they sit in.
    parkPointer(in: window.app)
    capture(slug("rules-codecs", in: appearance), of: window.inspectorPane)

    parkPointer(in: window.app)
    capture(slug("output-name", in: appearance), of: window.editor("rules.outputNameEditor"))
  }

  /**
   The preset menu, open. It is captured from the window rather than the
   inspector: the menu is its own window, so only the part of it lying over
   whatever is being captured is in the image.
   */
  private func capturePresetMenu(
    _ app: XCUIApplication,
    of mainWindow: XCUIElement,
    in appearance: SubTrack.Appearance
  ) {
    PresetsScreen(app: app).openMenu()
    assertOpenMenuFits(inside: mainWindow)
    capture(slug("preset-menu", in: appearance), of: mainWindow)
    dismissTransientUI(in: app)
  }

  /**
   One file's own track plan, with a track skipped so the override reads as a
   departure from the queue's rules. The selection lands back on the first
   track, whose details are what the article's steps talk through.
   */
  private func captureTrackOverride(
    _ app: XCUIApplication,
    of window: MainWindowScreen,
    in appearance: SubTrack.Appearance
  ) {
    window.rowNamed("Arrival (2016).mkv")
      .assertExists("Expected a queue row for “Arrival (2016).mkv”.")
      .click()
    let override = window.showOverride()
    override.selectTrack(2)
    override.toggleInclude()
    override.selectTrack(1)
    parkPointer(in: app)
    capture(slug("track-override", in: appearance), of: window.inspectorPane)
  }

  /**
   The same file's whole plan. Taken after ``captureTrackOverride(_:of:in:)``,
   so the skipped track it left behind is in shot as a dimmed row — which is
   what the article's "dimmed rows are the ones being dropped" is pointing at.

   The lossless English track is selected because the detail pane below is half
   the shot, and an audio track is what fills it: a title, a channel layout, a
   sample rate, and a bit rate where a subtitle has none of them.
   */
  private func capturePreviewTab(
    _ app: XCUIApplication,
    of window: MainWindowScreen,
    in appearance: SubTrack.Appearance
  ) {
    window.showPreview().selectPreviewTrack(1)
    parkPointer(in: app)
    capture(slug("track-preview", in: appearance), of: window.inspectorPane)
  }

  // MARK: - Adding and Settings articles

  func testCapturesSettingsArticlesInLightAppearance() { captureSettingsArticles(in: .light) }
  func testCapturesSettingsArticlesInDarkAppearance() { captureSettingsArticles(in: .dark) }

  /**
   The empty window's Add menu and the three Settings tabs the articles walk
   through. Launched with a usable FFmpeg folder, so choosing one shows Settings
   accepting it rather than the failure the folder fixture otherwise produces.
   */
  private func captureSettingsArticles(in appearance: SubTrack.Appearance) {
    let app = SubTrack.launch(
      state: .empty,
      appearance: appearance,
      windowSize: Self.settingsWindowSize,
      ffmpegFolder: .valid
    )
    let mainWindow = app.windows["SubTrack"]
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    window.assertEmptyStateVisible()
    window.openAddMenu()
    assertOpenMenuFits(inside: mainWindow)
    capture(slug("add-videos", in: appearance), of: mainWindow)
    dismissTransientUI(in: app)

    let settings = SettingsScreen(app: app).open()
    capturePresetsTab(settings, in: appearance)
    captureFFmpegTab(settings, in: appearance)
    settings.showTab("CLI")
    parkPointer(in: app)
    capture(slug("settings-cli", in: appearance), of: settings.window)
  }

  /// The Presets tab with a starter preset selected, so its rules are on show.
  private func capturePresetsTab(
    _ settings: SettingsScreen,
    in appearance: SubTrack.Appearance
  ) {
    settings.showTab("Presets")
    PresetsSettingsScreen(app: settings.app).select("Streaming Service Rip — English Only")
    parkPointer(in: settings.app)
    capture(slug("settings-presets", in: appearance), of: settings.window)
  }

  /// The FFmpeg tab after a custom folder has been chosen and accepted.
  private func captureFFmpegTab(
    _ settings: SettingsScreen,
    in appearance: SubTrack.Appearance
  ) {
    settings.showTab("FFmpeg")
    settings.click("settings.ffmpegModeCustom")
    settings.click("settings.ffmpegChoose")
    parkPointer(in: settings.app)
    capture(slug("settings-ffmpeg", in: appearance), of: settings.window)
  }

  // MARK: - Troubleshooting article

  func testCapturesTroubleshootingArticlesInLightAppearance() {
    captureTroubleshootingArticles(in: .light)
  }

  func testCapturesTroubleshootingArticlesInDarkAppearance() {
    captureTroubleshootingArticles(in: .dark)
  }

  /**
   Four distinct troubles in one queue. The inspector is hidden so every row's
   status is legible at once — a reader arrives at this article scanning for
   which of them is theirs.
   */
  private func captureTroubleshootingArticles(in appearance: SubTrack.Appearance) {
    let app = SubTrack.launch(
      state: .helpProblems,
      appearance: appearance,
      windowSize: Self.problemsWindowSize
    )
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    SidebarScreen(app: app).ensureVisible().selectQueue(named: "Troubleshooting")
    window.toggleInspectorFromToolbar()
    parkPointer(in: app)
    capture(slug("problem-queue", in: appearance), of: app.windows["SubTrack"])
  }

  // MARK: - Naming

  /// The name a capture is filed under; a dark variant sits beside its light twin.
  private func slug(_ article: String, in appearance: SubTrack.Appearance) -> String {
    appearance == .dark ? "\(article)-dark" : article
  }

  /// Closes whatever menu or popover was just captured, so it doesn't cover the next shot.
  private func dismissTransientUI(in app: XCUIApplication) {
    app.typeKey(.escape, modifierFlags: [])
  }
}
