import SwiftUI

extension AppEnvironment {

  /**
   The codecs the inspector offers as transcode targets for `streamType`:
   every encoder the resolved `ffmpeg` build reports once it has been probed,
   and the built-in catalog until then — so the menus are never empty at
   launch and never a guess afterwards.
   */
  func transcodeTargets(for streamType: StreamOperation.StreamType) -> [ConversionTarget] {
    guard case .loaded(let probed) = capabilities.state else {
      return FileTrackSelection.availableTargets(
        for: streamType,
        capabilities: queue.encoderCapabilities
      )
    }
    return FileTrackSelection.availableTargets(for: streamType, capabilities: probed)
  }
}

extension ConversionTarget {

  /**
   How the target reads in an open menu: its `ffmpeg` name, and what that
   encoder is when the build told us.
   */
  var menuTitle: String {
    summary.isEmpty ? displayName : String(localized: "\(displayName) (\(summary))")
  }
}
