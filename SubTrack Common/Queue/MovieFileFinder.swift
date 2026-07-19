import Foundation
import UniformTypeIdentifiers

/**
 Expands a set of dropped/opened URLs into the movie files the queue accepts,
 recursing into folders. Matches by UTI conformance to `public.movie` or by a
 known container extension (covers formats without a system UTI, e.g. MKV).
 */
public enum MovieFileFinder {

  /// Container extensions ffmpeg handles that may lack a system `public.movie` UTI.
  public static let extraExtensions: Set<String> = [
    "mkv", "webm", "ts", "m2ts", "mts", "wmv", "asf", "flv", "ogv", "ogm", "vob",
    "mxf", "divx", "rmvb", "f4v"
  ]

  /**
   How many files to find between `onProgress` calls. The callback hops to the
   main actor, so reporting every file would cost more than the walk.
   */
  private static let progressInterval = 50

  /**
   Expands `urls` into the movie files the queue accepts, recursing into
   folders.

   - Parameter onProgress: Called periodically with the running count of
     movie files found so far. Runs on whatever thread the walk is on.
   */
  public static func expand(
    _ urls: [URL],
    onProgress: (@Sendable (Int) -> Void)? = nil
  ) -> [URL] {
    var found = [URL]()
    let fileManager = FileManager.default
    for url in urls {
      var isDirectory: ObjCBool = false
      let exists = fileManager.fileExists(
        atPath: url.path(percentEncoded: false),
        isDirectory: &isDirectory
      )
      guard exists else { continue }
      if isDirectory.boolValue {
        found.append(
          contentsOf: movieFiles(
            under: url,
            using: fileManager,
            alreadyFound: found.count,
            onProgress: onProgress
          )
        )
      } else if isMovie(url) {
        found.append(url)
      }
      onProgress?(found.count)
    }
    return found
  }

  /**
   The movie files inside `folder`, in the order someone looking at the folder
   would expect them.

   `FileManager` enumerates in the file system's own order, which for a season
   folder is neither episode nor alphabetical order — so a dropped season would
   otherwise queue up scrambled. Sorting by path rather than by name keeps each
   subfolder's files together, and `localizedStandardCompare` reads the numbers
   in a name as numbers, so episode 2 precedes episode 10.

   Only folder contents are sorted: files named individually keep the order the
   caller listed them in.
   */
  private static func movieFiles(
    under folder: URL,
    using fileManager: FileManager,
    alreadyFound: Int,
    onProgress: (@Sendable (Int) -> Void)?
  ) -> [URL] {
    var found = [URL]()
    let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)
    while let child = enumerator?.nextObject() as? URL {
      if isMovie(child) {
        found.append(child)
        if found.count.isMultiple(of: progressInterval) { onProgress?(alreadyFound + found.count) }
      }
    }
    return found.sorted {
      $0.path(percentEncoded: false)
        .localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending
    }
  }

  /// Whether `url` names a movie file the queue accepts.
  public static func isMovie(_ url: URL) -> Bool {
    let fileExtension = url.pathExtension.lowercased()
    if let type = UTType(filenameExtension: fileExtension), type.conforms(to: .movie) {
      return true
    }
    return extraExtensions.contains(fileExtension)
  }
}
