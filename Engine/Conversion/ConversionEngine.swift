public import Foundation

/**
 The engine surface the queue depends on, so it can be driven by a stub in
 tests.
 */
public protocol ConversionEngineProtocol: Sendable {

  /// Probes a source file into a ``Container``.
  func probe(_ url: URL) async throws -> Container

  /**
   Discards whatever the engine remembers about `url`, so the next
   ``probe(_:)`` reads the file again rather than answering from an earlier
   inspection. An engine that remembers nothing need do nothing.
   */
  func invalidateProbe(_ url: URL) async

  /// Runs `job`, streaming ``JobEvent``s until it finishes or fails.
  func run(_ job: SlimJob) -> AsyncThrowingStream<JobEvent, any Error>
}

extension ConversionEngineProtocol {
  /// Does nothing, which is correct for an engine that remembers no probes.
  public func invalidateProbe(_: URL) {}
}

/**
 The serialized owner of `ffmpeg`/`ffprobe` work. The non-`Sendable`
 `Reader`/`Converter`/`ProgressReportingProcessor` instances are created and
 used only within its methods and never escape, which is what keeps them safe
 under Swift 6 complete concurrency.
 */
actor ConversionEngine: ConversionEngineProtocol {

  /**
   Resolves the `ffmpeg`/`ffprobe` provider afresh for each job, so a change
   to the user's FFmpeg-location setting takes effect immediately. `Sendable`,
   so it is safe to call without hopping onto the actor.
   */
  nonisolated private let locatorProvider: @Sendable () -> any FFmpegLocator

  /**
   Where every inspection this engine performs goes through, so a burst of
   them stays bounded and a file already read isn't read again — including the
   read a run performs, which would otherwise repeat the one the queue did
   when the file was added.
   */
  nonisolated private let probes: ProbeCoordinator

  /// The current locator.
  nonisolated var locator: any FFmpegLocator { locatorProvider() }

  init(locatorProvider: @escaping @Sendable () -> any FFmpegLocator) {
    self.locatorProvider = locatorProvider
    self.probes = ProbeCoordinator { url in
      let reader = Reader(suppressStderr: true)
      reader.ffprobeURL = locatorProvider().ffprobeURL
      return try await reader.open(file: url)
    }
  }

  /// Probes a source file into a ``Container``.
  nonisolated func probe(_ url: URL) async throws -> Container {
    try await probes.container(at: url)
  }

  nonisolated func invalidateProbe(_ url: URL) async {
    await probes.invalidate(url)
  }

  /**
   Runs a ``SlimJob``, streaming ``JobEvent``s. Cancelling the consuming task
   (or terminating the stream) cancels the run and terminates `ffmpeg`.
   */
  nonisolated func run(_ job: SlimJob) -> AsyncThrowingStream<JobEvent, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          continuation.yield(.probing)
          let container = try await probe(job.input)
          continuation.yield(.probed(container))

          let operations = try self.operations(for: job, container: container)
          try validate(operations: operations)
          continuation.yield(.operations(operations))

          try await makeProcessor(for: job, container: container, operations: operations)
            .process(outputURL: job.output) { progress in
              continuation.yield(.progress(progress))
            }

          continuation.yield(.finished)
          continuation.finish()
        } catch {
          if Task.isCancelled || error is CancellationError || isProcessingCancellation(error) {
            continuation.finish(throwing: VideoProcessingError.cancelled)
          } else {
            continuation.yield(.failed(error.userMessage))
            continuation.finish(throwing: error)
          }
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /**
   What the job does to `container`: its explicit per-file selection when it
   carries one, otherwise whatever its rules derive.
   */
  nonisolated private func operations(
    for job: SlimJob,
    container: Container
  ) throws -> [StreamOperation] {
    if let selection = job.selection { return selection.operations() }
    return try (job.rules ?? .default).makeConverter(container: container).operations()
  }

  /// A processor configured to run `operations` over the job's input.
  nonisolated private func makeProcessor(
    for job: SlimJob,
    container: Container,
    operations: [StreamOperation]
  ) -> ProgressReportingProcessor {
    let processor = ProgressReportingProcessor(inputURL: job.input, operations: operations)
    processor.ffmpegURL = locator.ffmpegURL
    processor.ffprobeURL = locator.ffprobeURL
    processor.verifyOutput = job.verify
    processor.totalDuration = .seconds(container.durationSec)
    return processor
  }

  /**
   Whether the error is a ``VideoProcessingError/cancelled``, which the run
   surfaces by finishing the stream rather than emitting a `.failed` event.
   */
  nonisolated private func isProcessingCancellation(_ error: any Error) -> Bool {
    if case VideoProcessingError.cancelled = error { return true }
    return false
  }

  /**
   Rejects any transcode whose encoder this build cannot provide, so the
   failure is actionable rather than an opaque `ffmpeg` exit.
   */
  nonisolated func validate(operations: [StreamOperation]) throws {
    if let (_, codec) = locator.capabilities.firstUnsupported(in: operations) {
      throw FFmpegToolError.unsupportedEncoder(codec: codec)
    }
  }
}
