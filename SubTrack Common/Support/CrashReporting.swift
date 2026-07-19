import Foundation
import Sentry

/**
 Crash and error reporting for a shipped launch.

 Both app shells call ``start(isAppStoreBuild:)`` from their initializer. A
 preview, a UI test, or a unit test gets none: Sentry's profiling and structured
 logging do main-thread work that keeps the run loop from going idle, which
 stalls XCUITest's wait-for-idle, and a test run has no telemetry worth sending.
 */
public enum CrashReporting {

  /// The SubTrack project in the `timcodes` Sentry organization.
  private static let dsn =
    "https://84f21c1ec47da1703476b6403afb0c1a@o4510156629475328.ingest.us.sentry.io/4511805749657600"

  /// Whether a unit-test bundle is hosting this process.
  private static var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /**
   Starts reporting, unless this launch is a preview or a test run.

   - Parameter isAppStoreBuild: Tags every event with the edition that produced
     it, so App Store and Developer-ID crashes stay distinguishable — they
     bundle different `ffmpeg` builds and gate different features.
   */
  public static func start(isAppStoreBuild: Bool) {
    guard !AppEnvironment.isRunningInXcodePreview,
      !AppEnvironment.isRunningUITests,
      !isRunningUnitTests
    else { return }

    SentrySDK.start { options in
      options.dsn = dsn

      // Keep the SDK quiet in release: its diagnostics belong in development, not a
      // shipped console.
      options.debug = false

      // SubTrack has no accounts, and its privacy policy promises data not linked to
      // identity, so never attach the user's IP, device name, or similar context.
      options.sendDefaultPii = false

      options.tracesSampleRate = 0.2

      options.configureProfiling = {
        $0.sessionSampleRate = 0.2
        $0.lifecycle = .trace
      }

      options.enableLogs = true

      // Discard events from debug builds, which report debugger-induced app hangs — a
      // paused main thread trips the watchdog — that never reflect production behavior.
      options.beforeSend = { event in
        #if DEBUG
          return nil
        #else
          return event
        #endif
      }
    }

    SentrySDK.configureScope { scope in
      scope.setTag(value: isAppStoreBuild ? "mas" : "download", key: "edition")
    }
  }
}
