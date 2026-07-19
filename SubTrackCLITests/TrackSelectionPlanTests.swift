import Foundation
import Testing

/**
 What the rules on the command line decide to keep, read from `--dry-run`.

 A dry run resolves the whole chain — argument parsing, the ``SlimRules`` it
 builds, and the operations the converter derives — while only reading the
 input, so these cover the CLI's own logic at the speed of an `ffprobe` call.

 Every expectation refers to ``MovieFixture``'s documented layout: `0:1` is the
 English audio, `0:2` the French, `0:3` the untagged one, and `0:4`/`0:5` the
 English and French subtitles.
 */
struct TrackSelectionPlanTests {

  private func plan(_ arguments: [String], of movie: URL = MovieFixture.standard) throws
    -> [String]
  {
    let output = try MovieFixture.makeWorkingDirectory()
      .appending(path: "out.mkv", directoryHint: .notDirectory)
    let result = try CLI.run(
      ["--dry-run"] + arguments
        + [
          movie.path(percentEncoded: false),
          output.path(percentEncoded: false)
        ]
    )
    #expect(result.succeeded, "A dry run should succeed: \(result.standardError)")
    return result.plan
  }

  @Test
  func defaultRulesKeepEnglishAndDropEverythingElse() throws {
    #expect(
      try plan([]) == [
        "0:0 (video): copy",
        "0:1 (audio): copy",
        "0:4 (subtitle): copy"
      ]
    )
  }

  /**
   The one piece of parsing most easily broken: a repeatable option clears its
   built-in default the first time it appears, so asking for French yields
   French *instead of* English rather than in addition to it.
   */
  @Test
  func languageFlagReplacesTheDefaultRatherThanAddingToIt() throws {
    #expect(
      try plan(["-l", "fra"]) == [
        "0:0 (video): copy",
        "0:2 (audio): copy",
        "0:5 (subtitle): copy"
      ]
    )
  }

  /// Repeats accumulate, and their order is the priority order.
  @Test
  func repeatedLanguageFlagsAccumulate() throws {
    #expect(
      try plan(["-l", "eng", "-l", "fra"]) == [
        "0:0 (video): copy",
        "0:1 (audio): copy",
        "0:2 (audio): copy",
        "0:4 (subtitle): copy",
        "0:5 (subtitle): copy"
      ]
    )
  }

  /// Both spellings of a flag drive the same rule.
  @Test("Untagged tracks are kept on request", arguments: ["-n", "--no-language"])
  func noLanguageFlagKeepsTheUntaggedTrack(_ flag: String) throws {
    #expect(
      try plan([flag]) == [
        "0:0 (video): copy",
        "0:1 (audio): copy",
        "0:3 (audio): copy",
        "0:4 (subtitle): copy"
      ]
    )
  }

  /**
   Commentary and other extra audio is left out by default, and taken along on
   request. Both tracks here are English, so it is the disposition rather than
   the language that decides — the second is kept only when asked for.
   */
  @Test
  func extraAudioIsExcludedUnlessAskedFor() throws {
    #expect(
      try plan([], of: MovieFixture.withCommentary) == [
        "0:0 (video): copy",
        "0:1 (audio): copy",
        "0:3 (subtitle): copy"
      ]
    )
    #expect(
      try plan(["--include-other-audio"], of: MovieFixture.withCommentary) == [
        "0:0 (video): copy",
        "0:1 (audio): copy",
        "0:2 (audio): copy",
        "0:3 (subtitle): copy"
      ]
    )
  }

  /**
   A track whose codec isn't preferred is transcoded to the target codec — the
   fixture's H.264 video stops being acceptable once AV1 is the only preference.
   */
  @Test
  func nonPreferredVideoIsTranscodedToTheTarget() throws {
    #expect(try plan(["--video-codec", "av1"]).first == "0:0 (video): transcode to hevc")
    #expect(
      try plan(["--video-codec", "av1", "--video-transcode", "av1"]).first
        == "0:0 (video): transcode to av1"
    )
  }
}
