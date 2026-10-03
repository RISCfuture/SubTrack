import Foundation

extension Process {

  // Suspends until the process exits instead of blocking a thread on
  // `waitUntilExit()`. Inspect `terminationStatus` afterward for the exit code.
  func runUntilExit() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      terminationHandler = { _ in continuation.resume() }
      do {
        try run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

extension Process {

  // Runs the process and returns everything it wrote to standard output and
  // standard error. Both pipes are drained alongside the process so neither can
  // fill and stall the child. Assigns `standardOutput` and `standardError`, so
  // callers must not set them themselves.
  func runCapturingOutputAndError() async throws -> (output: Data, diagnostics: Data) {
    let outputPipe = Pipe(), diagnosticsPipe = Pipe()
    standardOutput = outputPipe
    standardError = diagnosticsPipe

    async let output = outputPipe.fileHandleForReading.readAllData()
    async let diagnostics = diagnosticsPipe.fileHandleForReading.readAllData()
    do {
      try await runUntilExit()
    } catch {
      // Nothing spawned, so no child will ever close the write ends. Closing
      // this process's copies is what lets the concurrent reads reach EOF —
      // otherwise they wait forever and take the whole call with them.
      try? outputPipe.fileHandleForWriting.close()
      try? diagnosticsPipe.fileHandleForWriting.close()
      throw error
    }
    return (try await output, try await diagnostics)
  }
}

extension FileHandle {

  // Reads all bytes until end of file without blocking the cooperative
  // executor.
  func readAllData() async throws -> Data {
    var data = Data()
    for try await byte in bytes { data.append(byte) }
    return data
  }
}
