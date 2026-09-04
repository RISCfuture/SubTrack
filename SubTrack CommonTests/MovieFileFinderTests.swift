import Foundation
import Testing

import SubTrack_Common

@Suite
struct MovieFileFinderTests {

  /**
   A folder holding `names`, created in an order deliberately unlike the one
   they should come back in.
   */
  private func makeFolder(containing names: [String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "finder-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in names {
      try Data("x".utf8).write(to: folder.appending(path: name))
    }
    return folder
  }

  @Test
  func `orders a folder the way its episodes are numbered`() throws {
    // `FileManager` enumerates in the file system's own order, so a season
    // folder arrives scrambled — and a plain string sort would still put
    // episode 10 ahead of episode 2.
    let folder = try makeFolder(containing: [
      "Show - S01E10.mkv", "Show - S01E02.mkv", "Show - S01E100.mkv", "Show - S01E01.mkv"
    ])

    let found = MovieFileFinder.expand([folder]).map(\.lastPathComponent)

    #expect(
      found == ["Show - S01E01.mkv", "Show - S01E02.mkv", "Show - S01E10.mkv", "Show - S01E100.mkv"]
    )
  }

  @Test
  func `keeps files named individually in the order they were given`() throws {
    let folder = try makeFolder(containing: ["b.mkv", "a.mkv"])
    let (b, a) = (folder.appending(path: "b.mkv"), folder.appending(path: "a.mkv"))

    // Sorting is a folder's business: files the user picked themselves are
    // already in the order they chose.
    #expect(MovieFileFinder.expand([b, a]).map(\.lastPathComponent) == ["b.mkv", "a.mkv"])
  }
}
