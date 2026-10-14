import AppKit
import XCTest
import XCUITestKit

/**
 Turning what is on screen into a Help-book image.

 `xcodebuild` forwards no shell environment into the runner, so a test can't be
 told where to write: every capture goes into the result bundle as an
 attachment, and `Scripts/export-help-screenshots.sh` recovers it from there by
 name.
 */
extension XCTestCase {
  /// How long to leave between the two captures a stability check compares.
  private static let stabilityInterval: TimeInterval = 0.25

  /// How many comparisons to make before calling the screen unsettled.
  private static let stabilityLimit = 20

  /// Where the pointer is parked: over the window's title bar, which has no hover state.
  private static let pointerPark = CGVector(dx: 0.5, dy: 0.015)

  /**
   Attaches `element`'s current appearance to the result bundle under `slug`,
   which is the name the exported file is written under.

   The slug is asserted to be bare `[a-z0-9-]+` — no extension, ever. The
   export recovers each name from the mangled one `xcresulttool` records, which
   re-reads a dot as an extension, so a slug carrying one is silently mis-filed.

   `.keepAlways` is load-bearing: attachments default to `.deleteOnSuccess`,
   and these tests pass by design, so the images would be absent from the
   bundle the export reads.
   */
  func capture(_ slug: String, of element: XCUIElement) {
    XCTAssertNotNil(
      slug.range(of: "^[a-z0-9-]+$", options: .regularExpression),
      "Screenshot slug “\(slug)” has to be lowercase letters, digits, and hyphens."
    )
    let attachment = XCTAttachment(screenshot: waitForStableImage(of: element))
    attachment.name = slug
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /**
   Captures `element` repeatedly until two captures running are byte-identical,
   and returns the settled one.

   Two captures of an untouched window are identical to the byte, so a
   difference means something on screen is still moving — an overlay scrollbar
   fading out, a sheet finishing its slide, a layout pass yet to land. Waiting
   for the screen to stop moving is strictly better than sleeping for a
   constant somebody has to keep tuning.
   */
  func waitForStableImage(of element: XCUIElement) -> XCUIScreenshot {
    var previous = element.screenshot()
    for _ in 0..<Self.stabilityLimit {
      Thread.sleep(forTimeInterval: Self.stabilityInterval)
      let current = element.screenshot()
      if current.pngRepresentation == previous.pngRepresentation { return current }
      previous = current
    }
    XCTFail("The screen never settled — something is still animating.")
    return previous
  }

  /**
   Moves the pointer somewhere nothing reacts to it. XCUITest leaves the
   pointer wherever the last click landed, so without this a shot ships a row
   or a button wearing a hover treatment the reader can't account for.
   */
  func parkPointer(in app: XCUIApplication) {
    app.windows["SubTrack"].coordinate(withNormalizedOffset: Self.pointerPark).hover()
  }

  /**
   Fails unless the open menu lies wholly inside `window`.

   A menu is its own window, so it is in a window screenshot only where the two
   overlap — a capture is a crop of the composited desktop at the window's
   frame. A menu that spills past an edge is silently cut in half in the
   shipped image, and this is what says so.
   */
  func assertOpenMenuFits(inside window: XCUIElement) {
    let menu = XCUIApplication().openMenu()
    XCTAssertTrue(
      window.frame.contains(menu.frame),
      "The open menu (\(menu.frame)) spills outside the window (\(window.frame))."
    )
  }
}

extension XCUIApplication {
  /// How long to leave between looks for a menu that has opened.
  private static let menuPollInterval: TimeInterval = 0.05

  /**
   The menu the app has open, waited for.

   Told from the app's other menus by its frame: every menu in the menu bar is
   in the tree from launch and reports an empty one until it is opened, and all
   fourteen of them precede the open menu. `menus.firstMatch` is therefore
   reliably a *closed* File or Edit menu rather than the popup just clicked —
   and a closed menu reports its frame as zero-sized at the bottom of the
   screen, which is outside every window and inside none.
   */
  @discardableResult
  func openMenu(timeout: TimeInterval = ScaledTimeouts.element) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    var open: [XCUIElement]
    repeat {
      open = menus.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
      if let only = open.first, open.count == 1 { return only }
      Thread.sleep(forTimeInterval: Self.menuPollInterval)
    } while Date() < deadline
    XCTFail("Expected the app to have one menu open, found \(open.count).")
    return menus.firstMatch
  }
}

/**
 What a Mac has to be set to before its captures can be shipped.

 None of these can be forced per-process — the accessibility settings live in a
 domain the argument domain doesn't reach, and the display's scale is the
 display's — so they are asserted instead. A machine that fails one turns a
 silent twenty-four-file diff into a skip that names what to change.
 */
enum ScreenshotPreconditions {

  /// Whether this Mac draws the app the way the shipped images are drawn.
  static var machineCanCapture: Bool { firstUnmetRequirement == nil }

  /// The first requirement this Mac fails, for the skip message to name.
  static var unmetRequirement: String { firstUnmetRequirement ?? "every requirement is met" }

  private static var firstUnmetRequirement: String? {
    requirements.first { !$0.isMet }?.name
  }

  private static var requirements: [(name: String, isMet: Bool)] {
    let workspace = NSWorkspace.shared
    return [
      ("a 2× Retina display as the main display", NSScreen.main?.backingScaleFactor == 2),
      (
        "the multicolour accent colour",
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
      ),
      ("Reduce Transparency off", !workspace.accessibilityDisplayShouldReduceTransparency),
      ("Increase Contrast off", !workspace.accessibilityDisplayShouldIncreaseContrast),
      (
        "Differentiate Without Colour off",
        !workspace.accessibilityDisplayShouldDifferentiateWithoutColor
      ),
      ("Reduce Motion off", !workspace.accessibilityDisplayShouldReduceMotion)
    ]
  }
}
