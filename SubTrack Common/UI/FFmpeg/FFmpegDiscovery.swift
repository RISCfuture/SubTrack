import Foundation

/// A runnable `ffmpeg`/`ffprobe` pair found on this Mac, and what it can do.
struct FFmpegInstallation: Sendable {
  /// The folder holding both tools, as it was searched rather than as it resolves.
  let directory: URL

  /// What probing this build reported.
  let capabilities: FFmpegCapabilities

  /// How many encoders this build offers, which is what breaks a version tie.
  var encoderCount: Int {
    let encoders = EncoderCapabilities(probed: capabilities)
    return encoders.videoEncoders.count + encoders.audioEncoders.count
  }
}

/**
 Finds the `ffmpeg` builds already installed on this Mac and picks the best of
 them, so choosing a custom build doesn't mean knowing where a package manager
 put it.

 Only meaningful in the unsandboxed build: the sandbox refuses to execute — or
 even to answer whether it could execute — anything outside the app bundle.
 */
enum FFmpegDiscovery {

  /**
   Where a Mac usually keeps an `ffmpeg`: Homebrew on both prefixes, MacPorts,
   and the system path.

   `$PATH` is deliberately not consulted. A launched app inherits launchd's
   `PATH`, not the shell's, so `which` would answer for an environment the
   user never sees.
   */
  static let searchDirectories = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/opt/local/bin",
    "/usr/bin"
  ]

  /**
   The newest usable `ffmpeg` among `directories`, or `nil` when none of them
   holds a pair that runs. Every candidate is probed concurrently, so this
   costs about one `ffmpeg -version` regardless of how many are installed.
   */
  static func best(in directories: [String] = searchDirectories) async -> FFmpegInstallation? {
    // The minimum of a better-ranks-earlier ordering is the best of them, and
    // `min` keeps the earliest of equals — so a dead heat falls to search order.
    await probeAll(runnableDirectories(among: directories)).min(by: isBetter)
  }

  /**
   Whether `lhs` is the better find: the newer build, and between two of the
   same version the one offering more encoders.
   */
  static func isBetter(_ lhs: FFmpegInstallation, than rhs: FFmpegInstallation) -> Bool {
    let left = lhs.capabilities.version?.comparableVersion ?? [],
      right = rhs.capabilities.version?.comparableVersion ?? []
    if left != right { return right.lexicographicallyPrecedes(left) }
    return lhs.encoderCount > rhs.encoderCount
  }

  /**
   Those of `directories` that hold a runnable `ffmpeg` and `ffprobe`, with any
   two whose `ffmpeg` resolves to the same binary collapsed to the first —
   `/usr/local/bin` is often a symlink farm pointing into Homebrew's.
   */
  private static func runnableDirectories(among directories: [String]) -> [URL] {
    let candidates = directories.map { URL(filePath: $0, directoryHint: .isDirectory) }
    var seen = Set<String>()
    return candidates.filter { directory in
      guard holdsRunnableTools(in: directory) else { return false }
      let binary = FFmpegTools.url(FFmpegTools.ffmpeg, in: directory).resolvingSymlinksInPath()
      return seen.insert(binary.path(percentEncoded: false)).inserted
    }
  }

  private static func holdsRunnableTools(in directory: URL) -> Bool {
    [FFmpegTools.ffmpeg, FFmpegTools.ffprobe].allSatisfy {
      FFmpegTools.isRunnable($0, in: directory)
    }
  }

  /// Probes every directory at once, restoring search order over completion order.
  private static func probeAll(_ directories: [URL]) async -> [FFmpegInstallation] {
    await withTaskGroup(of: (place: Int, found: FFmpegInstallation?).self) { group in
      for (place, directory) in directories.enumerated() {
        group.addTask { (place, await probe(directory)) }
      }
      var probed: [(place: Int, found: FFmpegInstallation)] = []
      for await result in group {
        if let found = result.found { probed.append((result.place, found)) }
      }
      return probed.sorted { $0.place < $1.place }.map(\.found)
    }
  }

  /// Runs the pair in `directory` for its real capabilities; `nil` if it won't run.
  private static func probe(_ directory: URL) async -> FFmpegInstallation? {
    guard
      case .success(let capabilities) = await FFmpegProbe(
        ffmpegURL: FFmpegTools.url(FFmpegTools.ffmpeg, in: directory)
      ).run()
    else { return nil }
    return FFmpegInstallation(directory: directory, capabilities: capabilities)
  }
}
