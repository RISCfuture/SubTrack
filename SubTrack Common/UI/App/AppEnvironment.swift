import Foundation
import SwiftData

/**
 Build-specific capabilities. The only thing that differs between the App
 Store and Developer-ID apps.
 */
public struct FeatureFlags: Sendable {
  /**
   The page explaining the downloadable, full-featured build, linked from every
   control gated off in the App Store build.
   */
  public static let fullVersionURL = URL(
    string: "https://riscfuture.github.io/SubTrack/#get-it"
  )!

  /// Whether the bundled `ffmpeg` provides the full (GPL) codec set.
  public var fullCodecSet: Bool

  /**
   Whether this is the sandboxed Mac App Store build. App Store policy forbids
   running a user-supplied `ffmpeg` or installing the command-line tool, so
   those controls are disabled and point at the downloadable build instead.
   */
  public var isAppStoreBuild: Bool

  public init(fullCodecSet: Bool, isAppStoreBuild: Bool = false) {
    self.fullCodecSet = fullCodecSet
    self.isAppStoreBuild = isAppStoreBuild
  }
}

/**
 The editable global keep-rules and the preset they came from. Observable so
 the inspector edits it live and the queue reads it when building jobs.
 */
@MainActor
@Observable
public final class RulesModel {
  /// The keep-rules the inspector edits and the queue builds jobs from.
  public var rules: SlimRules

  /// The preset ``rules`` currently match, or `nil` once they have been edited away from one.
  public var activePresetID: UUID?

  /// Creates a model holding `rules`, with no preset marked active.
  public init(rules: SlimRules = .default) {
    self.rules = rules
  }

  /// Applies a preset's rules and marks it active.
  public func apply(_ preset: Preset) {
    rules = preset.rules
    activePresetID = preset.id
  }
}

/**
 The inspector panel's mode: the queue-wide preset, or the selected file's own
 overrides.
 */
public enum InspectorMode: Sendable, CaseIterable {
  case rules
  case `override`
}

/// Transient, window-level UI state shared between the views and menu commands.
@MainActor
@Observable
public final class UIState {
  /// Whether the trailing inspector is shown.
  public var inspectorVisible = true

  /// Which panel the inspector is showing.
  public var inspectorMode: InspectorMode = .rules
  /**
   The queue whose sidebar row is in inline-rename mode, or `nil`. Set by the
   sidebar context menu and the Rename Queue command; the row shows an editing
   field while it matches.
   */
  public var renamingQueueID: UUID?
  /**
   The queue awaiting delete confirmation, or `nil`. Set when a delete targets
   a queue with unfinished work so the sidebar can present a confirmation.
   */
  public var queuePendingDeletion: UUID?

  /// Creates the state a freshly launched window starts in.
  public init() {}
}

/**
 The dependency container the app shells build and inject into the scene tree.
 The two app targets differ only in the `locator` and `featureFlags` passed here.
 */
@MainActor
@Observable
public final class AppEnvironment {
  /**
   Whether the process is an Xcode preview/playground execution host. The app
   shells skip their SwiftData/engine bootstrap in this case: a framework-view
   preview is hosted in the app but never renders the app scene, and creating a
   `ModelContainer` there is both unnecessary and unstable across the live
   canvas's repeated refreshes.
   */
  nonisolated public static var isRunningInXcodePreview: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
      || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
  }

  /**
   Whether the app was launched by the XCUITest harness, which passes the
   `-uiTesting` argument. The app shells build a stubbed, in-memory
   ``AppEnvironment`` in this case; see ``UITestHarness``.
   */
  nonisolated public static var isRunningUITests: Bool {
    ProcessInfo.processInfo.arguments.contains("-uiTesting")
  }

  /**
   The SwiftData container backing every store here. Held for the environment's
   lifetime: a `ModelContext` does not keep its container alive, and a released
   container closes the SQLite store out from under it, so the next fetch traps.
   */
  public let modelContainer: ModelContainer

  /// The app's live queues and the current selection.
  public let workspace: Workspace

  /// Hydrates the workspace's queues on launch and writes their changes back.
  public let persistence: QueuePersistenceController

  /// The app-wide gate on how many encodes run at once across every queue.
  public let governor: EncodeGovernor

  /// The stored keep-rule presets, offered by the preset menu and Settings.
  public let presets: PresetStore

  /**
   Watches iCloud on behalf of the preset store, or `nil` when the container
   is not CloudKit-backed — a preview, a UI test, or a unit test.
   */
  public let syncMonitor: CloudSyncMonitor?

  /**
   App-wide default output destination, applied to each newly created queue
   and edited in Settings ▸ General. Not the live per-job destination — that
   is each queue's own ``QueueDestination``.
   */
  public let defaultDestination: OutputDestinationStore

  /// The per-item security-scoped bookmarks each queued file's access needs.
  public let itemBookmarks: ItemBookmarkStore

  /// The user's chosen `ffmpeg` location, bound by Settings ▸ FFmpeg.
  public let ffmpegSettings = FFmpegSettingsStore()

  /**
   The resolved `ffmpeg` build's version and supported formats, probed once and
   shared by the Settings "Supported Formats" sheet and the inspector's
   codec pickers. Reloaded whenever the FFmpeg location changes.
   */
  public let capabilities = FFmpegCapabilitiesStore()

  /// What this build can do, which is all the two app targets disagree about.
  public let featureFlags: FeatureFlags

  /**
   The checker behind the Check for Updates command and the Settings ▸ Updates
   tab, or `nil` when this build cannot update itself — the App Store build,
   where the store does it, and every preview, UI test, and unit test. Both
   surfaces are omitted in that case.
   */
  public let updates: (any UpdateChecking)?

  /// Window-level UI state the views and the menu commands share.
  public let ui = UIState()

  /**
   The selected queue's coordinator. Preserves the single-window UI and
   commands, which operate on one queue, while the workspace owns the rest.
   */
  public var queue: QueueCoordinator { workspace.selectedCoordinator }

  /**
   The selected queue's keep-rules and active preset. Backs the inspector's
   Rules tab and the preset menu, which operate on the current queue.
   */
  public var rules: RulesModel { workspace.selectedCoordinator.settings.rules }

  /// The selected queue's output destination. Backs the destination bar.
  public var destination: QueueDestination { workspace.selectedCoordinator.settings.destination }

  /**
   - Parameter engine: The conversion engine each queue's coordinator drives.
     Defaults to the real `ffmpeg`-backed ``ConversionEngine``; UI tests inject
     a deterministic stub through this seam.
   - Parameter updates: The update checker backing the Check for Updates
     command and the Settings ▸ Updates tab. Only the downloadable build passes
     one; leaving it `nil` omits both surfaces.
   */
  public init(
    modelContainer: ModelContainer,
    featureFlags: FeatureFlags,
    engine: (any ConversionEngineProtocol)? = nil,
    updates: (any UpdateChecking)? = nil
  ) {
    self.modelContainer = modelContainer
    self.updates = updates
    let modelContext = modelContainer.mainContext
    let syncMonitor = Self.makeSyncMonitor(for: modelContainer)
    let presets = PresetStore(modelContext: modelContext, sync: syncMonitor)
    let defaultDestination = OutputDestinationStore()
    let itemBookmarks = ItemBookmarkStore()
    let governor = EncodeGovernor()
    let fullCodecSet = featureFlags.fullCodecSet
    // Resolves the current FFmpeg-location setting for every job.
    let engine =
      engine
      ?? ConversionEngine(
        locatorProvider: { FFmpegProvisioning.makeLocator(fullCodecSet: fullCodecSet) }
      )

    // Every queue's coordinator shares the one engine, governor, and source
    // access, and is seeded with the default preset and app-default destination;
    // the workspace and persistence layer own their lifecycle. Hydration
    // overrides the seeded settings for a queue restored from the store.
    let workspace = Workspace { id, name, sortIndex in
      let settings = QueueSettings(destinationBookmark: defaultDestination.bookmarkData)
      if let preset = presets.presets.first { settings.rules.apply(preset) }
      return QueueCoordinator(
        id: id,
        name: name,
        sortIndex: sortIndex,
        engine: engine,
        governor: governor,
        settings: settings,
        makeBookmark: { itemBookmarks.makeBookmark(for: $0) },
        beginSourceAccess: { itemBookmarks.beginAccess(to: $0) },
        beginOutputFolderAccess: { itemBookmarks.beginAccess(toOutputFolderOf: $0) },
        probeCapabilities: { await Self.probeEncoderCapabilities(fullCodecSet: fullCodecSet) }
      )
    }

    self.presets = presets
    self.syncMonitor = syncMonitor
    self.defaultDestination = defaultDestination
    self.itemBookmarks = itemBookmarks
    self.governor = governor
    self.featureFlags = featureFlags
    self.workspace = workspace
    self.persistence = QueuePersistenceController(modelContext: modelContext, workspace: workspace)

    // Hydrate queues (seeding one when the store is empty) before any view
    // reads `queue`. `load()` runs each queue's post-launch reconciliation,
    // which includes the initial capability probe via `ffmpegLocationChanged()`.
    persistence.load()

    // A CloudKit-backed store has no presets yet when the queues load, so the
    // queue seeded on a first launch is built without one. Give it the first
    // preset as soon as the presets arrive.
    syncMonitor?.whenInitialImportSettles { [weak self] in
      self?.applyFirstPresetToUnconfiguredQueues()
    }

    // Refresh capabilities across every queue and the shared formats store
    // whenever the FFmpeg location changes; capabilities are a property of the
    // resolved binary, not any one queue.
    ffmpegSettings.onChange = { [weak self] in
      guard let self else { return }
      self.workspace.coordinators.forEach { $0.ffmpegLocationChanged() }
      self.reloadCapabilities()
    }

    // Previews and UI tests have no dependable runnable ffmpeg and seed the store
    // directly — probing a real binary would also make what Settings reports vary
    // with the machine. A real run probes the resolved build once at launch.
    if !Self.isRunningInXcodePreview && !Self.isRunningUITests { reloadCapabilities() }
  }

  /**
   Probes the currently-resolved `ffmpeg` for its real encoder set. Runs the
   binary off the main actor and returns `nil` when it can't be run, so the
   caller keeps its last-known capabilities.
   */
  private static func probeEncoderCapabilities(fullCodecSet: Bool) async -> EncoderCapabilities? {
    let ffmpegURL = FFmpegProvisioning.makeLocator(fullCodecSet: fullCodecSet).ffmpegURL
    switch await FFmpegProbe(ffmpegURL: ffmpegURL).run() {
      case .success(let capabilities): return EncoderCapabilities(probed: capabilities)
      case .unavailable: return nil
    }
  }

  /**
   Builds a monitor when `container` has a CloudKit-backed configuration.
   Returns `nil` otherwise, which is how an in-memory container tells the
   preset store to seed its starters at once instead of waiting on an import
   that will never come.
   */
  private static func makeSyncMonitor(for container: ModelContainer) -> CloudSyncMonitor? {
    guard
      let identifier = container.configurations
        .compactMap(\.cloudKitContainerIdentifier)
        .first
    else { return nil }
    return CloudSyncMonitor(containerIdentifier: identifier)
  }

  /// Whether a queue has neither an active preset nor any edit to its rules.
  private static func isUnconfigured(_ settings: QueueSettings) -> Bool {
    settings.rules.activePresetID == nil && settings.rules.rules == .default
  }

  /**
   Applies the first stored preset to every queue that has none and still
   carries the default rules, matching what the coordinator factory gives a
   queue built once the presets are loaded. A queue the user has configured,
   and one restored with its own saved settings, keeps what it has.
   */
  private func applyFirstPresetToUnconfiguredQueues() {
    guard let preset = presets.presets.first else { return }
    for coordinator in workspace.coordinators where Self.isUnconfigured(coordinator.settings) {
      coordinator.settings.apply(preset)
    }
  }

  /// Re-probes the resolved `ffmpeg` build for the shared formats/codecs store.
  private func reloadCapabilities() {
    let fullCodecSet = featureFlags.fullCodecSet
    Task { await capabilities.load(fullCodecSet: fullCodecSet) }
  }
}
