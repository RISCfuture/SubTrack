import Foundation
import Testing

/**
 Real source files for tests that add items to a `QueueCoordinator` directly.

 `add` monitors each source *and its containing folder*, so a source placed
 straight into a busy shared directory — `/tmp` above all — is revalidated
 whenever anything unrelated writes there, and a path that was never created is
 then settled `.missing` mid-test. Files that exist, in a directory nothing else
 writes to, leave that watch nothing to act on.

 Everything here is minted inside a root belonging to the running test, which
 ``Trait/sourceFixtures`` removes once that test ends; asking for a fixture
 without the trait in scope throws rather than leaving a directory behind.

 A source whose folder doesn't exist needs none of this: the folder watch can't
 be armed, so those tests pass a bare path instead.
 */
enum SourceFixtures {

  @TaskLocal private static var root: URL?

  /**
   An empty directory of the caller's own, for sources that must stay siblings
   across several calls to ``make(_:in:)``.
   */
  static func makeDirectory() throws -> URL {
    guard let root else { throw ScopeMissing() }
    let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /**
   Real, empty source files sharing a directory of their own.

   One call is one directory, so sources made together stay siblings — which is
   what keeps the tests about output naming and collisions meaningful.
   */
  static func make(_ names: [String]) throws -> [URL] {
    try make(names, in: makeDirectory())
  }

  /// A lone source file in a directory of its own; see ``make(_:)``.
  static func make(_ name: String) throws -> URL {
    try make([name])[0]
  }

  /// Real, empty source files named `names`, in a directory the caller owns.
  static func make(_ names: [String], in directory: URL) throws -> [URL] {
    try names.map { name in
      let file = directory.appending(path: name, directoryHint: .notDirectory)
      try Data("x".utf8).write(to: file)
      return file
    }
  }

  /// `count` real, empty source files under names of their own; see ``make(_:in:)``.
  static func make(_ count: Int, in directory: URL) throws -> [URL] {
    try make((0..<count).map { _ in "subtrack-\(UUID().uuidString).mkv" }, in: directory)
  }

  /// See ``Trait/sourceFixtures``.
  struct Scope: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
      for _: Test,
      testCase _: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "subtrack-sources-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      try await SourceFixtures.$root.withValue(root) { try await function() }
    }
  }

  /// Thrown when a fixture is asked for outside ``Trait/sourceFixtures``.
  struct ScopeMissing: Error, CustomStringConvertible {
    var description: String {
      "SourceFixtures needs `.sourceFixtures` on the enclosing suite or test."
    }
  }
}

extension Trait where Self == SourceFixtures.Scope {

  /**
   Gives each test in scope a fixture root of its own and removes it, whatever
   the test's outcome, once the test ends.

   Every ``SourceFixtures`` call requires it.
   */
  static var sourceFixtures: Self { Self() }
}
