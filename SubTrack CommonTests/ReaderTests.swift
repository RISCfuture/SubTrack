import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct ReaderTests {

  /**
   An executable file that isn't a runnable binary, so the launch fails with
   `ENOEXEC` the way a truncated or wrong-architecture bundled `ffprobe`
   would — a launch failure no existence check can screen out.
   */
  private func makeUnlaunchableExecutable() throws -> URL {
    let url = URL.temporaryDirectory.appending(
      path: "ffprobe-\(UUID().uuidString)",
      directoryHint: .notDirectory
    )
    try Data("not a binary".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: url.path(percentEncoded: false)
    )
    return url
  }

  /**
   A failed launch has to surface as a thrown error. Standard output is read
   concurrently with the run, and a process that never spawned leaves no child
   to close the pipe's write end — so an unclosed pipe leaves that read
   waiting on an EOF that never arrives. A regression here hangs rather than
   fails, because the stuck read also strands the queue item in `.probing`.
   */
  @Test
  func `launch failure throws rather than hanging`() async throws {
    let ffprobeURL = try makeUnlaunchableExecutable()
    defer { try? FileManager.default.removeItem(at: ffprobeURL) }

    let reader = Reader(suppressStderr: true)
    reader.ffprobeURL = ffprobeURL

    await #expect(throws: (any Error).self) {
      try await reader.open(file: URL(filePath: "/tmp/nonexistent.mkv"))
    }
  }

  /**
   An `ffprobe` that isn't there at all gets the actionable FFmpeg error
   naming it, rather than a raw POSIX launch failure.
   */
  @Test
  func `missing ffprobe reports which executable is missing`() async throws {
    let reader = Reader(suppressStderr: true)
    reader.ffprobeURL = URL(filePath: "/nonexistent/ffprobe", directoryHint: .notDirectory)

    let error = await #expect(throws: FFmpegToolError.self) {
      try await reader.open(file: URL(filePath: "/tmp/nonexistent.mkv"))
    }
    #expect(error?.failureReason?.contains("ffprobe") == true)
  }
}
