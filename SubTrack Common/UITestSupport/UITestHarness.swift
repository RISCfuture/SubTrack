#if DEBUG
  import Foundation
  import SwiftData

  /**
   Builds the app's dependency graph for UI tests, replacing everything a test
   can't drive from outside the process: the on-disk store becomes in-memory,
   the `ffmpeg` engine becomes a deterministic ``StubConversionEngine``, and the
   out-of-process ``FilePanels`` become handlers that return generated fixture
   files. All of it is gated on the ``AppEnvironment/isRunningUITests`` launch
   argument, so the production path is untouched, and the whole file is compiled
   out of release builds.

   A test configures the run through launch environment values, read here:
   - `UITEST_STATE` — the queue arrangement to seed (`empty`, `oneReadyItem`,
     `multiQueue`, `duplicateNames`, `missingSource`, `audioLoss`,
     `incompatible`); defaults to `empty`.
   - `UITEST_ENGINE` — `fail` makes every stubbed run fail; otherwise runs
     succeed.
   - `UITEST_STEP_DELAY_MS` — how long each stubbed progress tick takes.
   - `UITEST_PROBE_DELAY_MS` — how long a stubbed probe takes, for a test that
     needs to catch an item while it is still being inspected.
   - `UITEST_LARGE_FOLDER` — makes "Add Folder…" return a folder of this many
     movies, so an ingest runs long enough for a test to see its progress sheet.
   */
  @MainActor
  public enum UITestHarness {

    // MARK: - Launch configuration

    /**
     The state a test asked to be seeded. An unrecognized value is a mistake in
     the test, not a reason to launch into an arbitrary arrangement, so it stops
     the run instead of quietly seeding an empty queue.
     */
    private static var launchState: LaunchState {
      guard let raw = ProcessInfo.processInfo.environment["UITEST_STATE"] else { return .empty }
      guard let state = LaunchState(rawValue: raw) else {
        preconditionFailure("Unrecognized UITEST_STATE “\(raw)”.")
      }
      return state
    }

    /**
     How many movies the large folder should hold, or `nil` when no test asked
     for one — in which case it is never generated and "Add Folder…" keeps
     returning the small fixture folder.
     */
    private static var largeFolderCount: Int? {
      ProcessInfo.processInfo.environment["UITEST_LARGE_FOLDER"].flatMap(Int.init)
    }

    // MARK: - Stub configuration

    private static var engineBehavior: StubConversionEngine.Behavior {
      ProcessInfo.processInfo.environment["UITEST_ENGINE"] == "fail" ? .fail : .succeed
    }

    /**
     The pause between stubbed progress ticks. A test that needs to catch a run
     mid-flight (to cancel it) sets a larger value so the run doesn't finish
     before the click lands.
     */
    private static var engineStepDelay: Duration {
      guard let raw = ProcessInfo.processInfo.environment["UITEST_STEP_DELAY_MS"], let ms = Int(raw)
      else {
        return StubConversionEngine.defaultStepDelay
      }
      return .milliseconds(ms)
    }

    /**
     How long a stubbed probe takes. A test that needs to look at an item while
     it is still being inspected sets this; everything else probes instantly.
     */
    private static var engineProbeDelay: Duration {
      guard let raw = ProcessInfo.processInfo.environment["UITEST_PROBE_DELAY_MS"],
        let ms = Int(raw)
      else {
        return .zero
      }
      return .milliseconds(ms)
    }

    /**
     A representative multi-track probe result: an H.264 video track, English and
     French audio, and English and French subtitles — enough to drive the
     keep/drop and convert flows.
     */
    private static var fixtureContainer: Container {
      PreviewSupport.container(
        audio: [
          PreviewSupport.AudioTrack(codec: "ac3", language: "eng", channels: 6),
          PreviewSupport.AudioTrack(codec: "aac", language: "fra", channels: 2)
        ],
        subtitles: [
          PreviewSupport.SubtitleTrack(codec: "subrip", language: "eng"),
          PreviewSupport.SubtitleTrack(codec: "subrip", language: "fra")
        ]
      )
    }

    // MARK: - Environment

    /**
     Builds a fully wired UI-test ``AppEnvironment`` for an app shell, keeping
     the shell's own ``FeatureFlags`` so the App-Store gating still differs
     between the two builds. Generates fixtures, installs the file-panel
     handlers and the stub engine, then seeds the requested launch state.
     */
    public static func makeEnvironment(featureFlags: FeatureFlags) -> AppEnvironment {
      generateFixtures()
      installFilePanels()

      let environment = AppEnvironment(
        modelContainer: .subTrackUITests(),
        featureFlags: featureFlags,
        engine: StubConversionEngine(
          container: fixtureContainer,
          behavior: engineBehavior,
          stepDelay: engineStepDelay,
          probeDelay: engineProbeDelay
        )
      )
      // The formats sheet and the codec pickers read the shared capability store,
      // which a real run fills by probing ffmpeg. A UI test seeds it instead, so
      // what they offer is fixed rather than whatever build the machine resolves.
      environment.capabilities.setForPreview(.loaded(.previewSample))
      seedLaunchState(into: environment)
      return environment
    }

    // MARK: - Fixtures

    /**
     Writes the tiny placeholder movie files the file panels return. Content is
     irrelevant — the stub engine supplies the tracks — so a handful of bytes
     with a recognized extension is enough to be ingested and stat-ed.
     */
    private static func generateFixtures() {
      let manager = FileManager.default
      try? manager.removeItem(at: Fixtures.root)
      for folder in [Fixtures.movies, Fixtures.folder, Fixtures.destination] + Fixtures.sameNamed {
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
      }
      for name in ["Interstellar.mkv", "Arrival.mkv", "Vanishing.mkv"] {
        writePlaceholder(named: name, in: Fixtures.movies)
      }
      for name in ["Dune.mkv", "Sicario.mkv"] { writePlaceholder(named: name, in: Fixtures.folder) }
      for folder in Fixtures.sameNamed { writePlaceholder(named: "Show.mkv", in: folder) }
      generateLargeFolder()
    }

    /**
     Fills the large folder with the number of movies a test asked for. Minting
     each row's bookmarks is what makes the ingest slow enough to watch, so the
     count is the test's dial on how long its progress sheet stays up.
     */
    private static func generateLargeFolder() {
      guard let count = largeFolderCount else { return }
      try? FileManager.default.createDirectory(
        at: Fixtures.largeFolder,
        withIntermediateDirectories: true
      )
      for index in 1...count {
        writePlaceholder(named: "Episode \(index).mkv", in: Fixtures.largeFolder)
      }
    }

    private static func writePlaceholder(named name: String, in folder: URL) {
      try? Data(repeating: 0, count: 1024).write(
        to: folder.appending(path: name, directoryHint: .notDirectory)
      )
    }

    private static func movieFixtures() -> [URL] {
      ["Interstellar.mkv", "Arrival.mkv"].map {
        Fixtures.movies.appending(path: $0, directoryHint: .notDirectory)
      }
    }

    private static func sameNamedFixtures() -> [URL] {
      Fixtures.sameNamed.map { $0.appending(path: "Show.mkv", directoryHint: .notDirectory) }
    }

    // MARK: - Panel handlers

    /**
     Points every ``FilePanels`` prompt at a fixture, so "Add Files…", "Add
     Folder…", and "Change Destination…" resolve without an `NSOpenPanel`.
     */
    private static func installFilePanels() {
      FilePanels.chooseMoviesHandler = { movieFixtures() }
      FilePanels.chooseFolderHandler = {
        largeFolderCount == nil ? Fixtures.folder : Fixtures.largeFolder
      }
      FilePanels.chooseDestinationHandler = { Fixtures.destination }
    }

    // MARK: - Launch state

    private static func seedLaunchState(into environment: AppEnvironment) {
      switch launchState {
        case .empty:
          break
        case .oneReadyItem:
          environment.queue.ingest([movieFixtures()[0]])
        case .multiQueue:
          // Only "Movies" holds anything, so which queue the window is showing
          // is visible rather than inferred.
          let movies = environment.workspace.newQueue(name: "Movies")
          environment.workspace.newQueue(name: "TV Shows")
          movies.ingest([movieFixtures()[0]])
          // Creating a queue selects it, so the window is put back on the
          // seeded default and a test starts from a known queue.
          environment.workspace.selectQueue(environment.workspace.coordinators[0].id)
        case .duplicateNames:
          // The destination is set first so both sources are named into it, which
          // is what makes their shared name a collision.
          environment.queue.settings.destination.setDestination(Fixtures.destination)
          environment.queue.ingest(sameNamedFixtures())
        case .missingSource:
          // Deleted only once the item has been added, so its source monitor is
          // already armed and reports the file going away.
          Task {
            await environment.queue.ingestAsync([Fixtures.vanishing])
            try? FileManager.default.removeItem(at: Fixtures.vanishing)
          }
        case .audioLoss:
          // The fixture's audio is English and French, so keeping only Japanese
          // leaves the planned output silent.
          environment.queue.settings.editRules { $0.languages = ["jpn"] }
          environment.queue.ingest([movieFixtures()[0]])
        case .incompatible:
          // The fixture's H.264 video is no longer preferred, so the plan has to
          // encode HEVC — which the pinned VideoToolbox-only build can't do.
          environment.queue.encoderCapabilitiesOverride = .videoToolboxOnly
          environment.queue.settings.editRules { $0.videoPreferredCodecs = ["av1"] }
          environment.queue.ingest([movieFixtures()[0]])
      }
    }

    // MARK: - Supporting types

    /**
     The fixture files the harness generates and hands back through
     ``FilePanels``, all inside the app's own sandbox container so the sandboxed
     app can read them and write output beside them without any user-granted
     access.
     */
    private enum Fixtures {
      static let root = FileManager.default.temporaryDirectory.appending(
        path: "UITestFixtures",
        directoryHint: .isDirectory
      )
      static let movies = root.appending(path: "movies", directoryHint: .isDirectory)
      static let folder = root.appending(path: "folder", directoryHint: .isDirectory)
      static let destination = root.appending(path: "destination", directoryHint: .isDirectory)

      /**
       A folder of many movies, generated only when a test asks for one, so an
       ingest takes long enough to be observed. Every other launch pays nothing
       for it.
       */
      static let largeFolder = root.appending(path: "large-folder", directoryHint: .isDirectory)

      /// The source seeded by `missingSource`, deleted once it has been added.
      static let vanishing = movies.appending(
        path: "Vanishing.mkv",
        directoryHint: .notDirectory
      )

      /**
       Two folders holding a file of the same name, so a queue can be seeded
       with sources the default name format collides on.
       */
      static let sameNamed = [
        root.appending(path: "same-a", directoryHint: .isDirectory),
        root.appending(path: "same-b", directoryHint: .isDirectory)
      ]
    }

    /// The queue arrangement a test asks for through `UITEST_STATE`.
    private enum LaunchState: String {
      case empty
      case oneReadyItem
      case multiQueue
      case duplicateNames

      /// One item whose source is deleted once it has been added, so it flips to `missing`.
      case missingSource

      /// One item under rules that keep none of its audio, so it carries the audio-loss warning.
      case audioLoss

      /// One item whose plan needs an encoder the resolved build doesn't have.
      case incompatible
    }
  }
#endif
