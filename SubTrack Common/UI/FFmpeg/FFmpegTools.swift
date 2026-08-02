import Foundation

/**
 The pair of executables a usable FFmpeg folder has to hold, and where they sit
 inside one. Shared by the Settings validation that reports on a folder the
 user chose and by ``FFmpegDiscovery``, which asks the same question of every
 folder it searches.
 */
enum FFmpegTools {
  /// The transcoder, and the inspector the engine reads media with.
  static let ffmpeg = "ffmpeg", ffprobe = "ffprobe"

  /// Where `name` would sit inside `directory`.
  static func url(_ name: String, in directory: URL) -> URL {
    directory.appending(path: name, directoryHint: .notDirectory)
  }

  /**
   Whether `directory` holds a `name` this process could actually execute.

   Inside the App Sandbox this is `false` for everything outside the app
   bundle, executable or not: the check is `access(X_OK)`, which the sandbox
   gates on its `process-exec` rule, and no folder the user picks is covered
   by one.
   */
  static func isRunnable(_ name: String, in directory: URL) -> Bool {
    FileManager.default.isExecutableFile(
      atPath: url(name, in: directory).path(percentEncoded: false)
    )
  }
}
