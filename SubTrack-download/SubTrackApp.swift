import SubTrack_Common
import SwiftData
import SwiftUI

/**
 The Developer-ID / notarized build: unsandboxed, so it can run an `ffmpeg`
 the user points it at, and bundling a full `ffmpeg` with the complete codec
 set. Differs from the App Store build only in the injected dependencies.
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
    let featureFlags = FeatureFlags(fullCodecSet: true, isAppStoreBuild: false)
    #if DEBUG
      if AppEnvironment.isRunningUITests {
        _environment = State(
          initialValue: UITestHarness.makeEnvironment(featureFlags: featureFlags)
        )
        return
      }
    #endif
    // Ahead of every defaults read and the model container: 1.0 was sandboxed,
    // and its data has to be in the unsandboxed locations before either looks.
    ContainerMigration.run()
    // Sited after the preview and UI-test guards so neither reaches the network.
    CrashReporting.start(isAppStoreBuild: featureFlags.isAppStoreBuild)
    let updates = GitHubUpdates()
    updates.startAutomaticChecks()
    _environment = State(
      initialValue: AppEnvironment(
        modelContainer: .subTrackApp(),
        featureFlags: featureFlags,
        updates: updates
      )
    )
  }
}
