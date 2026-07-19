import Foundation
import Synchronization

import SubTrack_Common

/**
 A controllable stand-in for the real engine.

 Tests turn its knobs from the main actor while the coordinator drives the same
 instance from its own tasks, so the mutable ones live behind a lock rather than
 in properties the queue reads unsynchronized.
 */
final class StubEngine: ConversionEngineProtocol {
  private let knobs: Mutex<Knobs>
  private let holdUntilCancelled: Bool

  /**
   What every probe and run reports, so a test can model a source whose
   contents changed underneath the queue.
   */
  var container: Container {
    get { knobs.withLock { $0.container } }
    set { knobs.withLock { $0.container = newValue } }
  }

  /**
   How long a probe takes, widening the window in which an item is still
   being inspected.
   */
  var probeDelay: Duration {
    get { knobs.withLock { $0.probeDelay } }
    set { knobs.withLock { $0.probeDelay = newValue } }
  }

  /// Whether a probe throws instead of answering.
  var probeFails: Bool {
    get { knobs.withLock { $0.probeFails } }
    set { knobs.withLock { $0.probeFails = newValue } }
  }

  init(container: Container, holdUntilCancelled: Bool = false) {
    self.knobs = Mutex(Knobs(container: container))
    self.holdUntilCancelled = holdUntilCancelled
  }

  func probe(_: URL) async throws -> Container {
    let delay = probeDelay
    if delay > .zero { try? await Task.sleep(for: delay) }
    if probeFails { throw VideoProcessingError.launchFailed(detail: "stub probe failure") }
    return container
  }

  func run(_: SlimJob) -> AsyncThrowingStream<JobEvent, any Error> {
    let container = container
    let hold = holdUntilCancelled
    return AsyncThrowingStream { continuation in
      let task = Task {
        continuation.yield(.probing)
        continuation.yield(.probed(container))
        continuation.yield(.progress(ConversionProgress(fraction: 0.5)))
        if hold {
          do { try await Task.sleep(for: .seconds(30)) } catch {
            continuation.finish(throwing: VideoProcessingError.cancelled)
            return
          }
        }
        continuation.yield(.finished)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The settings a test can change mid-run, held together under one lock.
  private struct Knobs {
    var container: Container
    var probeDelay: Duration = .zero
    var probeFails = false
  }
}
