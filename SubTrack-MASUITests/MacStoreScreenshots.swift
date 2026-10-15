import XCTest
import XCUIPromoKit
import XCUITestKit

/**
 Captures the App Store product page's screenshots from the App Store build, in
 the order the page shows them.

 Runs only under `promokit mac-stills`, which sets `PROMO_LOCALE`; anywhere
 else the class skips. A machine whose display, accent colour, or accessibility
 settings would change what is drawn skips it too.

 Each still is attached to the result bundle under its name, which
 `promo/storyboard.json` refers to. The storyboard sets the product page's
 order, and the first is what a Mac App Store search result shows — so the
 order is the story: the plan that sets SubTrack apart, the rules that write
 it, a file overriding them, and the queues that hold the work. Every shot
 after the first highlights the part of the window its caption is about.
 */
nonisolated final class MacStoreScreenshots: XCTestCase {
  /**
   The window every main-window shot is taken in: the sidebar, the table, and
   the inspector side by side, short enough to leave room for a caption above
   it on a 16:10 canvas.
   */
  private static let windowSize = CGSize(width: 1200, height: 630)

  /// The App Store edition, whose windows are captured.
  private static let bundleIdentifier = "codes.tim.SubTrack-MAS"

  /// How long a still may take to stop moving before its capture fails.
  private static let settleLimit: Duration = .seconds(5)

  /// The remux the inspector is opened on, seeded by the harness's `appStore` state.
  private static let featuredFile = "Nightjar (2019).mkv"

  private var app: XCUIApplication?

  /// Main-actor isolated because the capture preconditions read `NSScreen` and `NSWorkspace`.
  @MainActor
  override func setUp() async throws {
    continueAfterFailure = false
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment[PromoLaunch.localeVariable] != nil,
      "Only `promokit mac-stills` captures the Mac App Store stills."
    )
    try XCTSkipUnless(
      ScreenshotPreconditions.machineCanCapture,
      "App Store screenshots need a capture-ready Mac: \(ScreenshotPreconditions.unmetRequirement)."
    )
  }

  @MainActor
  override func tearDown() async throws {
    app?.terminate()
  }
}

@MainActor
extension MacStoreScreenshots {
  /// Every shot, taken in one launch: they are all of the same seeded queue.
  func testCaptureStills() async throws {
    let app = SubTrack.launch(state: .appStore, appearance: .dark, windowSize: Self.windowSize)
    self.app = app
    let mainWindow = app.windows["SubTrack"]
    let window = MainWindowScreen(app: app).waitUntilLoaded()
    SidebarScreen(app: app).ensureVisible().selectQueue(named: "Movies")

    try await capturePlan(of: window, mainWindow)
    try await captureRules(of: window, mainWindow)
    try await captureOverride(of: window, mainWindow)
    try await captureQueues(of: window, mainWindow)
  }

  /**
   One remux's whole plan before it runs: every track it holds, the ones the
   rules drop dimmed. The lossless English mix is selected so the detail pane
   below shows what is being kept.
   */
  private func capturePlan(of window: MainWindowScreen, _ mainWindow: XCUIElement) async throws {
    window.rowNamed(Self.featuredFile)
      .assertExists("Expected a queue row for “\(Self.featuredFile)”.")
      .click()
    window.showPreview().selectPreviewTrack(1)
    parkPointer(in: window.app)
    try await PromoStill.capture(
      "plan",
      of: mainWindow,
      ownedBy: Self.bundleIdentifier,
      settlingWithin: Self.settleLimit,
      in: self
    )
  }

  /// The queue's rules: languages, commentary, untagged tracks, and preferred codecs.
  private func captureRules(of window: MainWindowScreen, _ mainWindow: XCUIElement) async throws {
    let rules = window.showRules()
    parkPointer(in: window.app)
    try await PromoStill.capture(
      "rules",
      of: mainWindow,
      ownedBy: Self.bundleIdentifier,
      highlighting: [[rules.languagesRow]],
      settlingWithin: Self.settleLimit,
      in: self
    )
  }

  /**
   The same file departing from the rules: its commentary, which the queue
   drops, kept for this one file.
   */
  private func captureOverride(of window: MainWindowScreen, _ mainWindow: XCUIElement) async throws
  {
    let override = window.showOverride()
    override.selectTrack(2)
    XCTAssertFalse(override.toggleInclude(), "The commentary should start out dropped.")
    parkPointer(in: window.app)
    try await PromoStill.capture(
      "override",
      of: mainWindow,
      ownedBy: Self.bundleIdentifier,
      highlighting: [[override.trackPicker], [override.includeToggle]],
      settlingWithin: Self.settleLimit,
      in: self
    )
  }

  /**
   The preset menu, which sits at the top of the Rules tab, open over a window
   whose sidebar holds three queues.
   */
  private func captureQueues(of window: MainWindowScreen, _ mainWindow: XCUIElement) async throws {
    window.showRules()
    PresetsScreen(app: window.app).openMenu()
    assertOpenMenuFits(inside: mainWindow)
    try await PromoStill.capture(
      "queues",
      of: mainWindow,
      ownedBy: Self.bundleIdentifier,
      highlighting: [[SidebarScreen(app: window.app).queueList], [window.app.openMenu()]],
      settlingWithin: Self.settleLimit,
      in: self
    )
    window.app.typeKey(.escape, modifierFlags: [])
  }
}
