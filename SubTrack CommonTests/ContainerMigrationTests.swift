import Foundation
import Testing

@testable import SubTrack_Common

@Suite
struct ContainerMigrationTests {

  @Test
  func `copies stores without following symlinks or overwriting`() throws {
    let fileManager = FileManager.default
    let root = URL.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let source = root.appending(path: "container", directoryHint: .isDirectory),
      destination = root.appending(path: "support", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

    try "queues".write(to: source.appending(path: "local.store"), atomically: true, encoding: .utf8)
    try "container".write(
      to: source.appending(path: "presets.store"),
      atomically: true,
      encoding: .utf8
    )
    // macOS plants these in every container, pointing back into the real
    // Application Support; copying through one would duplicate a whole tree.
    try fileManager.createSymbolicLink(
      at: source.appending(path: "iCloud"),
      withDestinationURL: URL(filePath: "/nowhere", directoryHint: .isDirectory)
    )
    try "already here".write(
      to: destination.appending(path: "presets.store"),
      atomically: true,
      encoding: .utf8
    )

    try ContainerMigration.copyStores(from: source, to: destination)

    #expect(
      try String(contentsOf: destination.appending(path: "local.store"), encoding: .utf8)
        == "queues"
    )
    #expect(
      try String(contentsOf: destination.appending(path: "presets.store"), encoding: .utf8)
        == "already here",
      "An existing store is the one the app has been running on; the container's is the stale one."
    )
    #expect(
      !fileManager.fileExists(
        atPath: destination.appending(path: "iCloud").path(percentEncoded: false)
      )
    )
  }
}
