#if DEBUG
  import AppKit

  /**
   Stages the app for the Help book's screenshots: pins the appearance and the
   main window's size, and puts a plain backdrop behind the window so nothing
   of the developer's desktop reaches a shipped image.

   Everything here is gated on `UITEST_SCREENSHOTS`, which only the screenshot
   suite sets, so every other UI test launches exactly as it does without this
   file. ``UITestHarness`` owns the dependency graph; this owns the AppKit
   staging around it, and is installed from the same launch hook.

   A test configures the staging through two more launch environment values:
   - `UITEST_APPEARANCE` — `light` or `dark`, the appearance the whole process
     is pinned to.
   - `UITEST_WINDOW_SIZE` — the main window's content size as `"1280x860"`.
   */
  @MainActor
  enum ScreenshotStaging {

    /// The main queue window's title, which is how it is told from the app's others.
    private static let mainWindowTitle = "SubTrack"

    /// Retained so the observers below outlive ``install()``.
    private static var observers: [any NSObjectProtocol] = []

    /// The full-screen fill drawn behind the app's windows.
    private static var backdrop: NSWindow?

    /// Whether the main window has already been sized, so it is pinned once.
    private static var hasSizedMainWindow = false

    /// Whether the running launch is capturing Help-book screenshots.
    static var isEnabled: Bool {
      ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1"
    }

    /**
     The appearance to pin. An unrecognized value is a mistake in the test, not
     a reason to capture a set in whichever appearance the machine happens to
     be in, so it stops the run.
     */
    private static var appearance: Appearance {
      guard let raw = ProcessInfo.processInfo.environment["UITEST_APPEARANCE"] else {
        return .light
      }
      guard let appearance = Appearance(rawValue: raw) else {
        preconditionFailure("Unrecognized UITEST_APPEARANCE “\(raw)”.")
      }
      return appearance
    }

    /**
     The main window's content size, or `nil` when the test didn't ask for one.
     A malformed value would silently ship a differently-sized image, so it
     stops the run instead.
     */
    private static var windowSize: CGSize? {
      guard let raw = ProcessInfo.processInfo.environment["UITEST_WINDOW_SIZE"] else { return nil }
      let dimensions = raw.split(separator: "x").compactMap { Double($0) }
      guard dimensions.count == 2 else {
        preconditionFailure("Malformed UITEST_WINDOW_SIZE “\(raw)”; expected “1280x860”.")
      }
      return CGSize(width: dimensions[0], height: dimensions[1])
    }

    /// The main queue window, told from the app's others by its title.
    private static var mainWindow: NSWindow? {
      NSApplication.shared.windows.first { $0.title == mainWindowTitle }
    }

    /**
     Stages the process for capture. Called from ``UITestHarness/makeEnvironment(featureFlags:)``,
     which runs from `SubTrackApp.init()`, so nothing here may touch AppKit
     itself: it only subscribes to the launch AppKit is about to perform.
     */
    static func install() {
      guard isEnabled else { return }
      stageAsAppKitLaunches()
      pinMainWindowSize()
    }

    /**
     Pins the whole process to one appearance, which SwiftUI's
     `preferredColorScheme(_:)` can't do: the titlebar, the toolbar background,
     and the material behind the sidebar follow `NSApp.appearance`, and all
     three are inside a window screenshot.
     */
    private static func pinAppearance() {
      NSApplication.shared.appearance = NSAppearance(named: appearance.systemName)
    }

    /**
     Pins the appearance and installs the backdrop as AppKit launches.

     Both waits are load-bearing, because `NSApplication.shared` is what
     *creates* the application object: reaching for it from `SubTrackApp.init()`
     builds one before SwiftUI has called `NSApplicationMain`, and SwiftUI then
     launches into an application it did not make and puts no window on screen
     at all. `willFinishLaunching` is the first moment the appearance can be set
     safely, and still before anything has been drawn; `didFinishLaunching` is
     the earliest a window can be ordered onto the screen, and it re-pins
     because AppKit sets the appearance itself as it finishes launching.
     */
    private static func stageAsAppKitLaunches() {
      observe(NSApplication.willFinishLaunchingNotification) { pinAppearance() }
      observe(NSApplication.didFinishLaunchingNotification) {
        pinAppearance()
        installBackdrop()
      }
    }

    /**
     Fills the screen behind the app with a flat colour.

     A window screenshot is a crop of the composited desktop, so the four
     rounded corners outside the window's own shape carry whatever is behind
     it — and a capture of a popover, which macOS opens wherever it has room,
     reaches well past the app's own windows. Without this, every shipped image
     is a function of the developer's wallpaper and of whatever else they had
     open.

     Left at the ordinary window level, and merely ordered to the back. Below
     it — the obvious choice for something meant to sit behind everything — is
     below *every* application's ordinary windows, not just this app's, so the
     editor or browser the developer left open goes on showing through. Window
     level outranks which app is active; being in the active app's ordinary
     level is what puts this above other apps at all.
     */
    private static func installBackdrop() {
      guard backdrop == nil, let screen = NSScreen.main else { return }
      let window = NSWindow(
        contentRect: screen.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.level = .normal
      window.ignoresMouseEvents = true
      window.backgroundColor = appearance.backdropColor
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
      window.setAccessibilityElement(false)
      window.orderBack(nil)
      backdrop = window
    }

    /**
     Sizes and centres the main window the first time it comes up.

     Pinned here rather than left to the scene's `defaultSize`, which is
     advisory (it is honoured only when no frame was autosaved) and states a
     *content* size, so the window in the image is taller than the number in
     the source by a titlebar and a toolbar.

     The window's own autosaving and restorability are left alone. Revoking
     either writes a state AppKit reads back on the *next* launch — a window
     that told AppKit not to restore it is a window AppKit then reopens none
     of — which would make a capture run break every launch after it.
     ``UITestHarness`` clears the autosaved geometry at launch instead, which
     leaves nothing behind.
     */
    private static func pinMainWindowSize() {
      guard let size = windowSize else { return }
      observe(NSWindow.didBecomeKeyNotification) {
        guard !hasSizedMainWindow, let window = mainWindow else { return }
        hasSizedMainWindow = true
        window.setContentSize(size)
        window.center()
      }
    }

    /**
     Runs `handler` on the main actor for every `name` notification. The
     notification itself is never handed on: it carries an `NSWindow`, which
     can't cross out of the posting context, and everything the handlers want
     is reachable from ``NSApplication`` anyway.
     */
    private static func observe(_ name: Notification.Name, handler: @escaping @MainActor () -> Void)
    {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { handler() }
        }
      )
    }

    /// The appearance a test asks for through `UITEST_APPEARANCE`.
    private enum Appearance: String {
      case light
      case dark

      var systemName: NSAppearance.Name {
        switch self {
          case .light: .aqua
          case .dark: .darkAqua
        }
      }

      /**
       The fill behind the app's windows: a flat, mid-toned neutral that reads
       as a desktop without competing with the window on top of it.
       */
      var backdropColor: NSColor {
        switch self {
          case .light: NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1)
          case .dark: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1)
        }
      }
    }
  }
#endif
