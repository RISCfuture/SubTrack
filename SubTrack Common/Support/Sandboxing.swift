import Foundation
import Security

extension ProcessInfo {
  private static let sandboxed: Bool = {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let entitlement = SecTaskCopyValueForEntitlement(
      task,
      "com.apple.security.app-sandbox" as CFString,
      nil
    )
    return entitlement as? Bool ?? false
  }()

  /**
   Whether this process runs inside the App Sandbox.

   The two app builds differ here: the App Store one is sandboxed, and the
   downloadable one is not — it has to run an `ffmpeg` the user chose, which
   the sandbox forbids. Behavior that only means something inside a sandbox
   (security-scoped bookmarks, the per-app container) is conditioned on this.
   */
  public var isSandboxed: Bool { Self.sandboxed }
}
