import Foundation

/**
 Real source files for tests that add items to a `QueueCoordinator` directly.

 `add` monitors each source *and its containing folder*, so a source placed
 straight into a busy shared directory — `/tmp` above all — is revalidated
 whenever anything unrelated writes there, and a path that was never created is
 then settled `.missing` mid-test. Files that exist, in a directory nothing else
 writes to, leave that watch nothing to act on.

 A source whose folder doesn't exist needs none of this: the folder watch can't
 be armed, so those tests pass a bare path instead.
 */
enum SourceFixtures {

  /**
   Real, empty source files sharing a directory of their own.

   One call is one directory, so sources made together stay siblings — which is
   what keeps the tests about output naming and collisions meaningful.
   */
  static func make(_ names: [String]) throws -> [URL] {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "subtrack-sources-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try names.map { name in
      let file = directory.appending(path: name, directoryHint: .notDirectory)
      try Data("x".utf8).write(to: file)
      return file
    }
  }

  /// A lone source file in a directory of its own; see ``make(_:)``.
  static func make(_ name: String) throws -> URL {
    try make([name])[0]
  }
}
