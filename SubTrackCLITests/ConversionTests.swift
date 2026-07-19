import Foundation
import Testing

/**
 The tool actually doing its job: a real `ffmpeg` run, end to end.

 One test, deliberately — this is the only slow case here, and everything about
 *which* tracks get kept is settled far more cheaply by
 ``TrackSelectionPlanTests``. What this adds is proof that a plan is carried
 out: that the output is written, is readable, and holds what was planned.
 */
struct ConversionTests {

  /// One real run into a fresh directory, reporting both what it printed and where it wrote.
  private func convert(
    _ arguments: [String],
    of movie: URL = MovieFixture.standard
  ) throws -> (result: CLI.Result, output: URL) {
    let output = try MovieFixture.makeWorkingDirectory()
      .appending(path: "slimmed.mkv", directoryHint: .notDirectory)
    let result = try CLI.run(
      arguments + [
        movie.path(percentEncoded: false),
        output.path(percentEncoded: false)
      ]
    )
    return (result, output)
  }

  @Test
  func slimsAFileDownToTheKeptTracks() throws {
    let (result, output) = try convert([])

    #expect(result.succeeded, "The conversion failed: \(result.standardError)")
    #expect(
      FileManager.default.fileExists(atPath: output.path(percentEncoded: false)),
      "The slimmed file was never written."
    )
    // The default rules keep English only, so the French and untagged tracks are
    // gone and what remains is a straight copy of the originals.
    #expect(
      try MovieFixture.streams(of: output) == [
        "h264,video",
        "ac3,audio,eng",
        "subrip,subtitle,eng"
      ]
    )
  }

  /**
   Rules that keep every track unchanged would copy the file to a new name for
   nothing, so `--skip-noops` declines to run at all. The same invocation
   without the flag is what proves the flag is doing it, rather than the plan
   having failed for some other reason.
   */
  @Test
  func aConversionThatWouldChangeNothingIsSkipped() throws {
    // Keeping both languages and the untagged track leaves all six streams
    // copied, which is the definition of a no-op.
    let keepEverything = ["-l", "eng", "-l", "fra", "-n"]

    let skipped = try convert(keepEverything + ["--skip-noops"])
    #expect(
      skipped.result.succeeded,
      "Skipping a no-op is success: \(skipped.result.standardError)"
    )
    #expect(
      !FileManager.default.fileExists(atPath: skipped.output.path(percentEncoded: false)),
      "A skipped no-op should not write an output file."
    )

    let performed = try convert(keepEverything)
    #expect(performed.result.succeeded)
    #expect(
      FileManager.default.fileExists(atPath: performed.output.path(percentEncoded: false)),
      "Without the flag the same no-op conversion should still be carried out."
    )
  }

  /**
   The output is re-read after a run, and an empty stream fails the whole
   conversion rather than being handed over as a file that looks fine. The
   fixture's subtitle cue falls outside the video, so the track it writes holds
   no packets.
   */
  @Test
  func anEmptyOutputStreamFailsTheRun() throws {
    let attempt = try convert([], of: MovieFixture.withEmptySubtitleTrack)

    #expect(attempt.result.exitCode == 1)
    #expect(
      attempt.result.standardError.contains("no packets"),
      "The failure should name what was wrong with the output: \(attempt.result.standardError)"
    )
  }

  /// `--skip-verify` accepts that same output rather than failing on it.
  @Test
  func skipVerifyAcceptsAnOutputThatVerificationWouldReject() throws {
    let attempt = try convert(["--skip-verify"], of: MovieFixture.withEmptySubtitleTrack)

    #expect(attempt.result.succeeded, "Skipping verification should let the run finish.")
    #expect(
      FileManager.default.fileExists(atPath: attempt.output.path(percentEncoded: false)),
      "The unverified output should still have been written."
    )
  }

  /// Progress is reported on stderr, leaving stdout free to be piped somewhere.
  @Test
  func progressIsReportedOnStandardError() throws {
    let (result, _) = try convert([])

    #expect(result.succeeded)
    #expect(result.standardError.contains("Done."))
  }
}
