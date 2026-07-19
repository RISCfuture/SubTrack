import SubTrack_Common
import SwiftData
import SwiftUI

/**
 The Mac App Store build: sandboxed, bundling a reduced LGPL `ffmpeg` and
 transcoding via VideoToolbox. Differs from the Developer-ID build only in
 the injected dependencies.
 */
@main
struct SubTrackApp: App {
  @State private var environment: AppEnvironment?

  var body: some Scene {
    SubTrackScenes(environment: environment)
  }

  init() {
    // A framework-view preview is hosted in this app but never renders its scene;
    // skip the SwiftData/engine bootstrap so previews don't create a ModelContainer.
    guard !AppEnvironment.isRunningInXcodePreview else {
      _environment = State(initialValue: nil)
      return
    }
    let featureFlags = FeatureFlags(fullCodecSet: false, isAppStoreBuild: true)
    #if DEBUG
      if AppEnvironment.isRunningUITests {
        _environment = State(
          initialValue: UITestHarness.makeEnvironment(featureFlags: featureFlags)
        )
        return
      }
    #endif
    // Sited after the preview and UI-test guards so neither reaches the network.
    CrashReporting.start(isAppStoreBuild: featureFlags.isAppStoreBuild)
    _environment = State(
      initialValue: AppEnvironment(modelContainer: .subTrackApp(), featureFlags: featureFlags)
    )
  }
}
