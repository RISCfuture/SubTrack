import Foundation
import Subprocess
import System

/**
 Locates the path for an executable by name, searching `$PATH` the way spawning
 it would.

 - Parameter executable: The name of the executable.
 - Returns: The URL path to the executable, or `nil` if it is not found on `$PATH`.
 */
func which(_ executable: String) async -> URL? {
  guard let path = try? await Executable.name(executable).resolveExecutablePath(in: .inherit)
  else { return nil }
  return URL(filePath: path.string, directoryHint: .notDirectory)
}
