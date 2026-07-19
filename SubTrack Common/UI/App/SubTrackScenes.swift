import DockProgress
import SwiftUI

/**
 The reusable scene tree both app shells instantiate. The shells differ only
 in the `AppEnvironment` they build and pass in.
 */
public struct SubTrackScenes: Scene {
  /**
   Optional so the app shells can pass `nil` in Xcode previews, where the app
   scene is never shown and no ``AppEnvironment`` is built. The scene *tree*
   stays static (SceneBuilder allows no control flow); each window's content
   branches on the environment at the ViewBuilder level instead.
   */
  private let environment: AppEnvironment?

  public var body: some Scene {
    Window("SubTrack", id: SubTrackWindowID.queue) {
      if let environment {
        NavigationSplitView {
          QueueSidebarView()
            .environment(environment)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
          QueueWindowView()
            .environment(environment)
        }
        .frame(minWidth: 720, minHeight: 420)
        .dockProgress(environment.workspace.dockProgress)
      }
    }
    .defaultSize(width: 960, height: 620)
    .commands { SubTrackCommands(environment: environment) }

    Window("Activity Log", id: SubTrackWindowID.activity) {
      if let environment {
        ActivityLogView()
          .environment(environment)
          .frame(minWidth: 480, minHeight: 280)
      }
    }
    .defaultSize(width: 720, height: 420)
    .keyboardShortcut("l", modifiers: [.command, .shift])

    Settings {
      if let environment {
        SubTrackSettingsView()
          .environment(environment)
      }
    }

    Window("About SubTrack", id: SubTrackWindowID.about) {
      if let environment {
        AboutView()
          .environment(environment)
      }
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }

  /**
   Builds the scene tree around one dependency container.

   - Parameter environment: The container every window's content is given, or
     `nil` in an Xcode preview, where the app scene is never shown and each
     window renders empty.
   */
  public init(environment: AppEnvironment?) {
    self.environment = environment
  }
}

/// Stable identifiers for the app's singleton windows.
enum SubTrackWindowID {
  /// The main window: the queue sidebar and the selected queue's table.
  static let queue = "queue"

  /// The Activity Log window.
  static let activity = "activity"

  /// The About window, opened from the custom About menu item.
  static let about = "about"
}
