#if DEBUG
  import Foundation

  /**
   A deterministic ``ConversionEngineProtocol`` for UI tests. Probes return a
   fixed ``Container`` and a run streams a few progress ticks before finishing
   (or failing), writing a small placeholder file at the job's output so the
   queue's size and track-count cells populate. It never touches `ffmpeg`, so
   runs are instant and reproducible.

   Installed only in the launch-argument-gated UI-test mode (see
   ``UITestHarness``); it is compiled out of release builds entirely.
   */
  struct StubConversionEngine: ConversionEngineProtocol {

    /// The pause between progress ticks a run uses unless a test asks for a slower one.
    static let defaultStepDelay: Duration = .milliseconds(150)

    private static let progressSteps = [0.25, 0.5, 0.75, 1.0]

    let container: Container
    let behavior: Behavior
    /**
     The pause between progress ticks, stretching a run long enough for a test
     to observe the running state and cancel it before completion.
     */
    let stepDelay: Duration
    /**
     How long a probe takes, stretching the window in which an item is still
     being inspected long enough for a test to look at it. Instant by default,
     so every test that doesn't care about that window starts settled.
     */
    let probeDelay: Duration

    /**
     A few bytes standing in for slimmed output; its only job is to exist and be
     stat-able so the output-size cell resolves to a real number.
     */
    private var placeholderOutput: Data { Data(repeating: 0, count: 4096) }

    init(
      container: Container,
      behavior: Behavior = .succeed,
      stepDelay: Duration = Self.defaultStepDelay,
      probeDelay: Duration = .zero
    ) {
      self.container = container
      self.behavior = behavior
      self.stepDelay = stepDelay
      self.probeDelay = probeDelay
    }

    func probe(_: URL) async throws -> Container {
      if probeDelay > .zero { try? await Task.sleep(for: probeDelay) }
      return container
    }

    func run(_ job: SlimJob) -> AsyncThrowingStream<JobEvent, any Error> {
      let (container, behavior, stepDelay) = (container, behavior, stepDelay)
      return AsyncThrowingStream { continuation in
        let task = Task {
          continuation.yield(.probed(container))
          for fraction in Self.progressSteps {
            try? await Task.sleep(for: stepDelay)
            if Task.isCancelled { return continuation.finish() }
            continuation.yield(
              .progress(
                ConversionProgress(fraction: fraction, totalSize: placeholderBytes(at: fraction))
              )
            )
          }
          switch behavior {
            case .succeed:
              try? placeholderOutput.write(to: job.output)
              continuation.yield(.finished)
            case .fail:
              continuation.yield(
                .failed(
                  String(
                    localized: "The conversion failed. (Stubbed UI-test failure.)",
                    bundle: #bundle
                  )
                )
              )
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }

    /**
     A byte count that grows with progress, so the "writing…" size updates as a
     run streams rather than jumping straight to the final size.
     */
    private func placeholderBytes(at fraction: Double) -> Int {
      Int(Double(placeholderOutput.count) * fraction)
    }

    /**
     How a run resolves, letting a test exercise both the success and failure
     paths without a real encoder.
     */
    enum Behavior: Sendable {
      case succeed
      case fail
    }
  }
#endif
