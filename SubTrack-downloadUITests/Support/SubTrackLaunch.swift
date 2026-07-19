import XCTest
import XCUITestKit

/**
 Launches the app in stubbed UI-test mode. Every test starts here, so the
 `-uiTesting` argument and fixture configuration live in one place rather than
 being repeated per test.
 */
enum SubTrack {

  static func launch(
    state: State = .empty,
    engine: Engine = .succeed,
    stepDelayMilliseconds: Int? = nil,
    probeDelayMilliseconds: Int? = nil,
    largeFolderSize: Int? = nil
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-uiTesting"]
    app.launchEnvironment["UITEST_STATE"] = state.rawValue
    app.launchEnvironment["UITEST_ENGINE"] = engine.rawValue
    if let stepDelayMilliseconds {
      app.launchEnvironment["UITEST_STEP_DELAY_MS"] = String(stepDelayMilliseconds)
    }
    if let probeDelayMilliseconds {
      app.launchEnvironment["UITEST_PROBE_DELAY_MS"] = String(probeDelayMilliseconds)
    }
    if let largeFolderSize {
      app.launchEnvironment["UITEST_LARGE_FOLDER"] = String(largeFolderSize)
    }
    // The toolbar's Add control is present whether the queue is empty or populated,
    // so it's the stable "window is up" signal.
    app.launchAndWaitUntilReady(readyElement: { $0.descendant(id: "toolbar.add") })
    return app
  }

  /// The queue arrangement the harness seeds at launch (mirrors `UITEST_STATE`).
  enum State: String {
    case empty
    case oneReadyItem
    case multiQueue

    /**
     Two sources that share a file name but not a folder, saved into one
     destination — the arrangement the default output-name format collides on.
     */
    case duplicateNames

    /// One item whose source is deleted once it has been added.
    case missingSource

    /// One item under rules that keep none of its audio.
    case audioLoss

    /// One item whose plan needs an encoder the resolved build doesn't have.
    case incompatible
  }

  /// How stubbed runs resolve (mirrors `UITEST_ENGINE`).
  enum Engine: String {
    case succeed
    case fail
  }
}
