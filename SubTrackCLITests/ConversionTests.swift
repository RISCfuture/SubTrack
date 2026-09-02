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

  /**
   One real run, reporting both what it printed and where it wrote. The output
   lands in a fresh directory unless the caller names one, which is how a
   second run is aimed at what a first one already produced.
   */
  private func convert(
    _ arguments: [String],
    of movie: URL = MovieFixture.standard,
    to destination: URL? = nil
  ) throws -> (result: CLI.Result, output: URL) {
    let output = try destination ?? freshOutputURL()
    let result = try CLI.run(
      arguments + [
        movie.path(percentEncoded: false),
        output.path(percentEncoded: false)
      ]
    )
    return (result, output)
  }

  /// A `slimmed.mkv` in a directory of its own, so one run can't disturb another.
  private func freshOutputURL() throws -> URL {
    try MovieFixture.makeWorkingDirectory()
      .appending(path: "slimmed.mkv", directoryHint: .notDirectory)
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

   Verification is a gate rather than a postmortem: the rejected output is
   staged elsewhere and never moved to the destination, so a failed run leaves
   nothing behind for the user to mistake for a result.
   */
  @Test
  func anEmptyOutputStreamFailsTheRun() throws {
    let attempt = try convert([], of: MovieFixture.withEmptySubtitleTrack)

    #expect(attempt.result.exitCode == 1)
    #expect(
      attempt.result.standardError.contains("no packets"),
      "The failure should name what was wrong with the output: \(attempt.result.standardError)"
    )
    #expect(
      !FileManager.default.fileExists(atPath: attempt.output.path(percentEncoded: false)),
      "A rejected output should not be left at the destination."
    )
  }

  /**
   A run that fails leaves whatever was already at the destination alone.

   Re-running a file is an ordinary flow — a cancelled or failed item can just
   be started again — so writing straight to the destination would truncate a
   good earlier result before `ffmpeg` had produced anything to replace it
   with, and a run that then failed would have destroyed it for nothing.
   */
  @Test
  func aFailedRunLeavesAnEarlierOutputIntact() throws {
    let first = try convert([])
    #expect(first.result.succeeded, "The first conversion failed: \(first.result.standardError)")
    // Compared byte for byte: the losing run writes the same three streams, so
    // a stream listing alone can't tell a survivor from its replacement.
    let original = try Data(contentsOf: first.output)

    let second = try convert([], of: MovieFixture.withEmptySubtitleTrack, to: first.output)

    #expect(second.result.exitCode == 1)
    #expect(
      try Data(contentsOf: first.output) == original,
      "The earlier output should survive a re-run that fails."
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
