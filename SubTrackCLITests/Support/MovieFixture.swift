import Foundation

/**
 Generated movies for the CLI to slim.

 Built with `ffmpeg` at run time rather than committed: the tests need exact
 track layouts — including an audio track carrying *no* language, one marked as
 commentary, and a subtitle track holding no packets — and generating them keeps
 binaries out of the repository.

 Each fixture is built once per test run and never reused across runs: a cached
 file would outlive a change to the recipes below and quietly test the wrong
 layout.
 */
enum MovieFixture {

  /**
   The everyday fixture, which most tests read:

   | Stream | Type     | Codec  | Language   |
   |--------|----------|--------|------------|
   | 0:0    | video    | h264   | —          |
   | 0:1    | audio    | ac3    | eng        |
   | 0:2    | audio    | ac3    | fra        |
   | 0:3    | audio    | ac3    | *untagged* |
   | 0:4    | subtitle | subrip | eng        |
   | 0:5    | subtitle | subrip | fra        |

   Every codec is one the default rules prefer, so nothing is transcoded unless
   a test asks for it and each kept track reads as `copy`.
   */
  static let standard: URL = built("standard") { directory, subtitles in
    [
      "-f", "lavfi", "-i", "testsrc=size=128x96:rate=10:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=880:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=220:duration=1",
      "-i", subtitles, "-i", subtitles,
      "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:a", "-map", "4:s", "-map", "5:s",
      "-c:v", "libx264", "-c:a", "ac3", "-c:s", "srt",
      "-metadata:s:a:0", "language=eng",
      "-metadata:s:a:1", "language=fra",
      "-metadata:s:s:0", "language=eng",
      "-metadata:s:s:1", "language=fra",
      directory
    ]
  }

  /**
   Two English audio tracks where the second is flagged as commentary:

   | Stream | Type     | Codec  | Language | Disposition |
   |--------|----------|--------|----------|-------------|
   | 0:0    | video    | h264   | —        | —           |
   | 0:1    | audio    | ac3    | eng      | default     |
   | 0:2    | audio    | ac3    | eng      | comment     |
   | 0:3    | subtitle | subrip | eng      | —           |

   The disposition is what makes 0:2 "other" audio — a track is judged extra by
   carrying a disposition that is none of default, dub, or original, not by its
   language.
   */
  static let withCommentary: URL = built("commentary") { directory, subtitles in
    [
      "-f", "lavfi", "-i", "testsrc=size=128x96:rate=10:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=880:duration=1",
      "-i", subtitles,
      "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s",
      "-c:v", "libx264", "-c:a", "ac3", "-c:s", "srt",
      "-metadata:s:a:0", "language=eng",
      "-metadata:s:a:1", "language=eng",
      "-metadata:s:s:0", "language=eng",
      "-disposition:a:0", "default",
      "-disposition:a:1", "comment",
      directory
    ]
  }

  /**
   A video, an English audio track, and an English subtitle track whose only cue
   falls outside the video's one second — so the muxed subtitle stream carries no
   packets at all.

   Slimming this produces an output that is structurally right but has an empty
   stream, which is exactly what the post-process verification exists to catch.
   */
  static let withEmptySubtitleTrack: URL = built(
    "empty-subtitle",
    subtitleCue: "1\n00:00:09,000 --> 00:00:10,000\nlate\n"
  ) { directory, subtitles in
    [
      "-f", "lavfi", "-i", "testsrc=size=128x96:rate=10:duration=1",
      "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
      "-i", subtitles,
      "-map", "0:v", "-map", "1:a", "-map", "2:s",
      "-c:v", "libx264", "-c:a", "ac3", "-c:s", "srt",
      "-shortest",
      "-metadata:s:a:0", "language=eng",
      "-metadata:s:s:0", "language=eng",
      directory
    ]
  }

  /// A scratch directory for one test's output.
  static func makeWorkingDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "subtrack-cli-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /**
   The streams of `movie` as `"<codec>,<type>[,<language>]"` — the order
   `ffprobe` emits them in, which is its own rather than the order they are
   asked for. An untagged track simply has no third field.
   */
  static func streams(of movie: URL) throws -> [String] {
    let result = try CLI.execute(
      CLI.vendoredFFprobe,
      arguments: [
        "-v", "error",
        "-show_entries", "stream=codec_type,codec_name:stream_tags=language",
        "-of", "csv=p=0",
        movie.path(percentEncoded: false)
      ]
    )
    return result.standardOutput
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  // MARK: - Generation

  /**
   Muxes one fixture, handing `arguments` the output path and the path of a
   subtitle file holding `subtitleCue`. A fixture that can't be built is a broken
   test rig rather than a failing expectation, so it stops the run.
   */
  private static func built(
    _ name: String,
    subtitleCue: String = "1\n00:00:00,000 --> 00:00:01,000\nhello\n",
    arguments: (_ output: String, _ subtitles: String) -> [String]
  ) -> URL {
    do {
      let directory = try makeWorkingDirectory()
      let subtitles = directory.appending(path: "subtitles.srt", directoryHint: .notDirectory)
      try subtitleCue.write(to: subtitles, atomically: true, encoding: .utf8)

      let movie = directory.appending(path: "\(name).mkv", directoryHint: .notDirectory)
      let result = try CLI.execute(
        CLI.vendoredFFmpeg,
        arguments: ["-y", "-loglevel", "error"]
          + arguments(
            movie.path(percentEncoded: false),
            subtitles.path(percentEncoded: false)
          )
      )
      guard result.succeeded else {
        fatalError("Could not build the “\(name)” fixture: \(result.standardError)")
      }
      return movie
    } catch {
      fatalError("Could not build the “\(name)” fixture: \(error)")
    }
  }
}
