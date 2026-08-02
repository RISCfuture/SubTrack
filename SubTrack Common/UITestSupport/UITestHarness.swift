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
     `incompatible`, `helpQueue`, `helpProblems`); defaults to `empty`.
   - `UITEST_ENGINE` — `fail` makes every stubbed run fail; otherwise runs
     succeed.
   - `UITEST_STEP_DELAY_MS` — how long each stubbed progress tick takes.
   - `UITEST_PROBE_DELAY_MS` — how long a stubbed probe takes, for a test that
     needs to catch an item while it is still being inspected.
   - `UITEST_LARGE_FOLDER` — makes "Add Folder…" return a folder of this many
     movies, so an ingest runs long enough for a test to see its progress sheet.
   - `UITEST_FFMPEG_FOLDER` — `valid` makes the folder chooser return a folder
     that really holds `ffmpeg` and `ffprobe`; otherwise it returns one that
     holds neither.

   ``ScreenshotStaging`` reads `UITEST_SCREENSHOTS`, `UITEST_APPEARANCE`, and
   `UITEST_WINDOW_SIZE` for the AppKit staging the Help book's screenshots need.
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
     between the two builds. Stages the process for screenshots, generates
     fixtures, installs the file-panel handlers and the stub engine, then seeds
     the requested launch state.

     ``ScreenshotStaging/install()`` runs first because this is called from
     `SubTrackApp.init()`, before AppKit has made a window — the only moment at
     which the appearance can be pinned ahead of anything being drawn.
     */
    public static func makeEnvironment(featureFlags: FeatureFlags) -> AppEnvironment {
      clearPersistedWindowGeometry()
      ScreenshotStaging.install()
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

    /**
     Drops the window geometry AppKit autosaves: the windows' frames and the
     split view's divider positions.

     AppKit brings a window back at whatever size it was last left at, so
     without this a test inherits the window the test before it left behind —
     and the screenshot suite leaves a 1280-point-wide one, which is enough to
     keep the sidebar expanded for a test that never asked for it. Clearing on
     the way *in* rather than pinning on the way out is what keeps a launch from
     affecting any launch after it.
     */
    private static func clearPersistedWindowGeometry() {
      let autosavedPrefixes = ["NSWindow Frame ", "NSSplitView Subview Frames "]
      let defaults = UserDefaults.standard
      for key in defaults.dictionaryRepresentation().keys
      where autosavedPrefixes.contains(where: key.hasPrefix) {
        defaults.removeObject(forKey: key)
      }
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
      let folders =
        [Fixtures.movies, Fixtures.folder, Fixtures.destination, Fixtures.ffmpegFolder]
        + Fixtures.sameNamed
      for folder in folders {
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
      }
      for name in ["Interstellar.mkv", "Arrival.mkv", "Vanishing.mkv"] {
        writePlaceholder(named: name, in: Fixtures.movies)
      }
      for name in ["Dune.mkv", "Sicario.mkv"] { writePlaceholder(named: name, in: Fixtures.folder) }
      for folder in Fixtures.sameNamed { writePlaceholder(named: "Show.mkv", in: folder) }
      generateFFmpegBinaries()
      generateLargeFolder()
    }

    /**
     Fills the ffmpeg fixture folder with executables named `ffmpeg` and
     `ffprobe`, so a test can choose a custom folder Settings accepts. They are
     never run — the harness seeds the capability store directly — so a script
     that exits cleanly is all the folder check looks for.
     */
    private static func generateFFmpegBinaries() {
      let manager = FileManager.default
      for name in ["ffmpeg", "ffprobe"] {
        let binary = Fixtures.ffmpegFolder.appending(path: name, directoryHint: .notDirectory)
        try? "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try? manager.setAttributes(
          [.posixPermissions: 0o755],
          ofItemAtPath: binary.path(percentEncoded: false)
        )
      }
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
      FilePanels.chooseFolderHandler = { chosenFolder() }
      FilePanels.chooseDestinationHandler = { Fixtures.destination }
    }

    /**
     The folder every "choose a folder" prompt resolves to. A test that asked
     for a usable `ffmpeg` folder gets the one holding the stub binaries;
     otherwise the movie folder, which holds neither — the arrangement the
     custom-FFmpeg tests rely on to be reported as unusable.
     */
    private static func chosenFolder() -> URL {
      guard ProcessInfo.processInfo.environment["UITEST_FFMPEG_FOLDER"] != "valid" else {
        return Fixtures.ffmpegFolder
      }
      return largeFolderCount == nil ? Fixtures.folder : Fixtures.largeFolder
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
        case .helpQueue:
          seedHelpQueue(into: environment)
        case .helpProblems:
          seedHelpProblems(into: environment)
      }
    }

    // MARK: - Help-book fixtures

    /**
     The queue the Help book's screenshots are taken of: a Blu-ray rip queue
     part-way through a run, beside an empty one.

     Seeded through ``PreviewSupport/populate(_:with:queueName:)`` rather than
     the ingest path, which hands back 1 KB placeholders the stub engine slims
     to 4 KB — every row would read "Input 1 KB → Output 4 KB", a screenshot
     that contradicts the product. Stating the sources outright also keeps a
     developer's user name and sandbox container out of a shipped image.
     */
    private static func seedHelpQueue(into environment: AppEnvironment) {
      let queue = PreviewSupport.populate(
        environment,
        with: HelpFixtures.queueItems,
        queueName: "Blu-ray Rips"
      )
      environment.workspace.newQueue(name: "TV Shows")
      discardSeededQueue(from: environment.workspace)
      queue.settings.editRules {
        $0.languages = ["eng", "fra", "jpn"]
        $0.preserveNoLanguages = false
        $0.includeOtherAudio = true
      }
      queue.settings.destination.setDestination(HelpFixtures.destination)
      environment.workspace.selectQueue(queue.id)
    }

    /**
     One queue of four distinct troubles, for the "If a file won't slim"
     article: a source that has gone, a file the resolved build can't encode, a
     run that failed, and a file whose output would be silent.

     The rules and capabilities are pinned so revalidation agrees with the
     statuses the fixture states rather than re-deriving contradicting ones: the
     H.264 file has to transcode to an encoder a VideoToolbox-only build hasn't
     got, while the AV1 files are copied through and stay ready.
     */
    private static func seedHelpProblems(into environment: AppEnvironment) {
      let queue = PreviewSupport.populate(
        environment,
        with: HelpFixtures.problemItems,
        queueName: "Troubleshooting"
      )
      discardSeededQueue(from: environment.workspace)
      queue.settings.editRules {
        $0.languages = ["eng"]
        $0.videoPreferredCodecs = ["av1"]
        $0.videoConversionCodec = "libx265"
      }
      queue.encoderCapabilitiesOverride = .videoToolboxOnly
      environment.workspace.selectQueue(queue.id)
    }

    /**
     Drops the queue an empty store seeds on a first launch. It is an artifact
     of the store being empty, not something a reader of the Help book should
     see in the sidebar.
     */
    private static func discardSeededQueue(from workspace: Workspace) {
      guard let seeded = workspace.coordinators.first(where: { $0.name == Workspace.seedQueueName })
      else {
        return
      }
      workspace.deleteQueue(seeded.id)
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

      /**
       A folder holding stub `ffmpeg` and `ffprobe` executables, so a test can
       choose a custom FFmpeg folder Settings accepts rather than reports as
       unusable.
       */
      static let ffmpegFolder = root.appending(path: "ffmpeg", directoryHint: .isDirectory)

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

    /**
     The queues the Help book's screenshots are taken of, stated outright rather
     than ingested.

     The panels hand back 1 KB placeholders and the stub engine writes 4 KB, so
     an ingested queue would have every row read "Input 1 KB → Output 4 KB" — a
     screenshot that contradicts the product. Declaring the sources also keeps a
     developer's user name and sandbox container out of an image that ships
     inside the app.
     */
    @MainActor
    private enum HelpFixtures {
      /// The folder the screenshots show sources sitting in.
      static let sourceFolder = "/Users/Shared/Movies"

      /// The folder the Help book's queue writes its slimmed output to.
      static let destination = URL(filePath: "/Users/Shared/Movies/Slimmed")

      /**
       The eight films the queue screenshots show, in queue order.

       No row is left `.probing`, and none may be. That status draws an
       indeterminate spinner, which never stops turning and so never lets two
       captures of the window come out identical — the stability check
       ``XCTestCase/waitForStableImage(of:)`` waits for would time out rather
       than settle. A run part-way through is shown by the `.running` row's
       determinate ring instead, which holds still at the fraction it is given.
       */
      static var queueItems: [PreviewSupport.ItemSpec] {
        [
          PreviewSupport.ItemSpec(
            name: "Arrival (2016).mkv",
            folder: sourceFolder,
            status: .done,
            sourceByteCount: 32_600_000_000,
            outputByteCount: 21_400_000_000,
            tracksRemoved: 10,
            container: arrivalContainer
          ),
          PreviewSupport.ItemSpec(
            name: "Blade Runner 2049 (2017).mkv",
            folder: sourceFolder,
            status: .done,
            sourceByteCount: 41_800_000_000,
            outputByteCount: 29_700_000_000,
            tracksRemoved: 12,
            container: rippedContainer(
              named: "Blade Runner 2049 (2017).mkv",
              sizeBytes: 41_800_000_000,
              audioLanguages: ["eng", "eng", "fra", "deu", "spa", "ita"],
              subtitleLanguages: ["eng", "eng", "fra", "deu", "spa", "ita", "nld", "dan", "swe"]
            )
          ),
          PreviewSupport.ItemSpec(
            name: "Dune (2021).mkv",
            folder: sourceFolder,
            status: .running,
            progress: 0.42,
            sourceByteCount: 38_200_000_000,
            writtenByteCount: 15_900_000_000,
            container: container(named: "Dune (2021).mkv", sizeBytes: 38_200_000_000)
          ),
          PreviewSupport.ItemSpec(
            name: "Interstellar (2014).mkv",
            folder: sourceFolder,
            status: .waiting,
            sourceByteCount: 44_100_000_000
          ),
          PreviewSupport.ItemSpec(
            name: "Sicario (2015).mkv",
            folder: sourceFolder,
            status: .ready,
            sourceByteCount: 27_300_000_000,
            container: container(named: "Sicario (2015).mkv", sizeBytes: 27_300_000_000)
          ),
          PreviewSupport.ItemSpec(
            name: "The Martian (2015).mkv",
            folder: sourceFolder,
            status: .ready,
            sourceByteCount: 33_900_000_000,
            container: container(named: "The Martian (2015).mkv", sizeBytes: 33_900_000_000)
          ),
          PreviewSupport.ItemSpec(
            name: "Prisoners (2013).mkv",
            folder: sourceFolder,
            status: .waiting,
            sourceByteCount: 30_500_000_000
          ),
          PreviewSupport.ItemSpec(
            name: "Enemy (2013).mkv",
            folder: sourceFolder,
            status: .ready,
            sourceByteCount: 19_800_000_000,
            container: container(named: "Enemy (2013).mkv", sizeBytes: 19_800_000_000)
          )
        ]
      }

      /// The six films behind the troubleshooting screenshot.
      static var problemItems: [PreviewSupport.ItemSpec] {
        [
          PreviewSupport.ItemSpec(
            name: "Chungking Express (1994).mkv",
            folder: sourceFolder,
            status: .done,
            sourceByteCount: 18_700_000_000,
            outputByteCount: 12_100_000_000,
            tracksRemoved: 6,
            container: rippedContainer(
              named: "Chungking Express (1994).mkv",
              sizeBytes: 18_700_000_000,
              audioLanguages: ["yue", "cmn", "eng", "fra"],
              subtitleLanguages: ["eng", "fra", "deu", "spa", "jpn"]
            )
          ),
          PreviewSupport.ItemSpec(
            name: "Vanishing Point (1971).mkv",
            folder: sourceFolder,
            status: .missing
          ),
          PreviewSupport.ItemSpec(
            name: "Solaris (1972).mkv",
            folder: sourceFolder,
            status: .incompatible(
              "The “libx265” encoder isn’t available in the current FFmpeg"
            ),
            sourceByteCount: 24_300_000_000,
            container: container(named: "Solaris (1972).mkv", sizeBytes: 24_300_000_000)
          ),
          PreviewSupport.ItemSpec(
            name: "Ikiru (1952).mkv",
            folder: sourceFolder,
            status: .ready,
            sourceByteCount: 16_400_000_000,
            container: japaneseOnlyContainer
          ),
          PreviewSupport.ItemSpec(
            name: "Rififi (1955).mkv",
            folder: sourceFolder,
            status: .failed("ffmpeg exited with code 1"),
            sourceByteCount: 15_200_000_000
          ),
          PreviewSupport.ItemSpec(
            name: "Le Samouraï (1967).mkv",
            folder: sourceFolder,
            status: .ready,
            sourceByteCount: 17_900_000_000,
            container: copyableContainer(named: "Le Samouraï (1967).mkv", sizeBytes: 17_900_000_000)
          )
        ]
      }

      /**
       The 14-stream container the track-override screenshot inspects: two English
       audio tracks (one of them a commentary), four more audio languages, and
       seven subtitle tracks — a plan worth overriding.
       */
      private static var arrivalContainer: Container {
        PreviewSupport.container(
          filename: "\(sourceFolder)/Arrival (2016).mkv",
          sizeBytes: 32_600_000_000,
          audio: [
            PreviewSupport.AudioTrack(
              codec: "truehd",
              language: "eng",
              channels: 8,
              title: "Dolby TrueHD 7.1"
            ),
            PreviewSupport.AudioTrack(
              codec: "ac3",
              language: "eng",
              channels: 6,
              title: "Director’s Commentary",
              roles: [.comment]
            ),
            PreviewSupport.AudioTrack(codec: "dts", language: "fra", channels: 6),
            PreviewSupport.AudioTrack(codec: "ac3", language: "deu", channels: 6),
            PreviewSupport.AudioTrack(codec: "ac3", language: "spa", channels: 6),
            PreviewSupport.AudioTrack(codec: "ac3", language: "ita", channels: 6)
          ],
          subtitles: [
            PreviewSupport.SubtitleTrack(
              codec: "subrip",
              language: "eng",
              title: "English (SDH)",
              roles: [.hearingImpaired]
            ),
            PreviewSupport.SubtitleTrack(
              codec: "hdmv_pgs_subtitle",
              language: "eng",
              roles: [.forced]
            ),
            PreviewSupport.SubtitleTrack(codec: "subrip", language: "fra"),
            PreviewSupport.SubtitleTrack(codec: "subrip", language: "deu"),
            PreviewSupport.SubtitleTrack(codec: "subrip", language: "spa"),
            PreviewSupport.SubtitleTrack(codec: "subrip", language: "ita"),
            PreviewSupport.SubtitleTrack(codec: "subrip", language: "nld")
          ]
        )
      }

      /**
       A film whose only audio is Japanese, so English-only rules plan an output
       with no audio at all and the row carries the silent-output warning.
       */
      private static var japaneseOnlyContainer: Container {
        PreviewSupport.container(
          filename: "\(sourceFolder)/Ikiru (1952).mkv",
          sizeBytes: 16_400_000_000,
          video: [PreviewSupport.VideoTrack(codec: "av1", width: 1440, height: 1080)],
          audio: [PreviewSupport.AudioTrack(codec: "ac3", language: "jpn", channels: 2)],
          subtitles: [PreviewSupport.SubtitleTrack(codec: "subrip", language: "eng")]
        )
      }

      /**
       A rip's full set of streams, for a row that states how many tracks it
       dropped.

       The Output Tracks column is the container's stream count *less* the
       row's `tracksRemoved`, so a row claiming to have removed more tracks
       than its container holds reports a negative count — which is why the two
       finished rows carry the many-language audio and subtitle sets a disc
       actually ships rather than the four-stream default.
       */
      private static func rippedContainer(
        named name: String,
        sizeBytes: Int,
        audioLanguages: [String],
        subtitleLanguages: [String]
      ) -> Container {
        PreviewSupport.container(
          filename: "\(sourceFolder)/\(name)",
          sizeBytes: sizeBytes,
          audio: audioLanguages.map {
            PreviewSupport.AudioTrack(codec: "ac3", language: $0, channels: 6)
          },
          subtitles: subtitleLanguages.map {
            PreviewSupport.SubtitleTrack(codec: "subrip", language: $0)
          }
        )
      }

      /// A typical film's streams, named and sized after the row they belong to.
      private static func container(named name: String, sizeBytes: Int) -> Container {
        PreviewSupport.container(
          filename: "\(sourceFolder)/\(name)",
          sizeBytes: sizeBytes
        )
      }

      /**
       A film the troubleshooting queue's pinned build can slim: its AV1 video is
       already a preferred codec, so the plan copies it rather than reaching for
       an encoder that build hasn't got.
       */
      private static func copyableContainer(named name: String, sizeBytes: Int) -> Container {
        PreviewSupport.container(
          filename: "\(sourceFolder)/\(name)",
          sizeBytes: sizeBytes,
          video: [PreviewSupport.VideoTrack(codec: "av1", width: 1920, height: 1080)]
        )
      }
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

      /// The Help book's queue: a Blu-ray rip queue part-way through a run.
      case helpQueue

      /// The Help book's troubleshooting queue: four distinct troubles at once.
      case helpProblems
    }
  }
#endif
