import Foundation
import Testing

/**
 How `subtrack` answers a command line it can't act on: help, and the four ways
 an invocation can be malformed. None of these read the input file, so none
 need a fixture.
 */
struct CommandLineUsageTests {

  @Test("Help is printed and succeeds", arguments: ["-h", "--help"])
  func helpFlagPrintsUsage(_ flag: String) throws {
    let result = try CLI.run([flag])

    #expect(result.succeeded)
    #expect(result.standardOutput.contains("USAGE: subtrack"))
    #expect(result.standardOutput.contains("--include-other-audio"))
  }

  /**
   Help is control flow rather than an error, and it is answered before the
   arguments around it are validated — so asking for it never fails on the
   command line it was asked from.
   */
  @Test
  func helpIsAnsweredBeforeOtherArgumentsAreChecked() throws {
    let result = try CLI.run(["--dry-run", "-h", "only-one-positional"])

    #expect(result.succeeded)
    #expect(result.standardOutput.contains("USAGE: subtrack"))
  }

  @Test(
    "An input and an output are both required",
    arguments: [[], ["input.mkv"], ["input.mkv", "output.mkv", "extra.mkv"]]
  )
  func wrongNumberOfPathsFails(_ paths: [String]) throws {
    let result = try CLI.run(paths)

    #expect(result.exitCode == 1)
    #expect(!result.standardError.isEmpty, "A usage failure should say something on stderr.")
  }

  @Test
  func unknownOptionFailsAndNamesIt() throws {
    let result = try CLI.run(["--nonsense", "input.mkv", "output.mkv"])

    #expect(result.exitCode == 1)
    #expect(result.standardError.contains("--nonsense"))
  }

  /// A flag whose value is missing must be reported as such, not silently ignored.
  @Test
  func flagWithoutItsValueFailsAndNamesIt() throws {
    let result = try CLI.run(["input.mkv", "output.mkv", "--language"])

    #expect(result.exitCode == 1)
    #expect(result.standardError.contains("--language"))
  }
}
