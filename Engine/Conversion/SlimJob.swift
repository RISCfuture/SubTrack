import Foundation

/**
 A single unit of work for the `ConversionEngine`: slim `input` into
 `output`. Exactly one of `selection` (an explicit per-file override) or
 `rules` (rule-derived operations) drives the work; `selection` wins when set.
 */
public struct SlimJob: Sendable, Identifiable {

  /// Identifies the job for as long as it is in the queue.
  public let id: UUID

  /// The source file to slim.
  public let input: URL

  /// Where the slimmed copy is written.
  public let output: URL

  /// An explicit per-file track override. When non-`nil`, used verbatim.
  public var selection: FileTrackSelection?

  /// Rules used to derive operations when `selection` is `nil`.
  public var rules: SlimRules?

  /// Whether to re-probe and verify the output after `ffmpeg` exits.
  public var verify: Bool

  /**
   Creates a job.

   - Parameter id: Identifies the job for as long as it is in the queue.
   - Parameter input: The source file to slim.
   - Parameter output: Where the slimmed copy is written.
   - Parameter selection: An explicit per-file track override, used verbatim
     when non-`nil`.
   - Parameter rules: Rules used to derive operations when `selection` is `nil`.
   - Parameter verify: Whether to re-probe and verify the output after `ffmpeg`
     exits.
   */
  public init(
    id: UUID = UUID(),
    input: URL,
    output: URL,
    selection: FileTrackSelection? = nil,
    rules: SlimRules? = nil,
    verify: Bool = true
  ) {
    self.id = id
    self.input = input
    self.output = output
    self.selection = selection
    self.rules = rules
    self.verify = verify
  }
}

/// Events streamed from the `ConversionEngine` as a ``SlimJob`` runs.
public enum JobEvent: Sendable {

  /// `ffprobe` has started reading the source.
  case probing

  /// The source was probed into `container`.
  case probed(Container)

  /// The operations to be performed were resolved.
  case operations([StreamOperation])

  /// A conversion progress update.
  case progress(ConversionProgress)

  /// The job finished successfully.
  case finished

  /// The job failed with a human-readable message.
  case failed(String)
}
