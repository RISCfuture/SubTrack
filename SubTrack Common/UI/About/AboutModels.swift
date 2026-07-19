import Foundation

/**
 The FFmpeg attribution and license notice shown in the About window. The
 text differs per build: the App Store build bundles an LGPL FFmpeg with no
 GPL components; the download build bundles a GPL FFmpeg built with libx264
 and libx265.
 */
struct FFmpegAcknowledgement: Sendable, Equatable {

  /// Mac App Store build: LGPL FFmpeg, VideoToolbox, no GPL components.
  static let lgpl = Self(
    summary: String(
      localized: """
        SubTrack bundles FFmpeg, built under the GNU Lesser General Public License, version 2.1 or \
        later (LGPL v2.1+), with no GPL-licensed components. Video encoding uses Apple \
        VideoToolbox. This software uses libraries from the FFmpeg project under the LGPLv2.1.
        """
    ),
    licenseTitle: String(localized: "FFmpeg — LGPL v2.1+"),
    licenseBody: String(
      localized: """
        FFmpeg is free software licensed under the GNU Lesser General Public License (LGPL) \
        version 2.1 or later. The FFmpeg build bundled with this copy of SubTrack is configured \
        without any GPL-licensed components — it contains no libx264, libx265, or other GPL \
        libraries.

        This software uses libraries from the FFmpeg project under the LGPLv2.1.

        Copyright © 2000–2024 the FFmpeg developers.

        The full text of the GNU LGPL v2.1 is available at \
        https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html. FFmpeg source and license \
        information are available at https://www.ffmpeg.org.
        """
    )
  )

  /// Developer-ID download build: GPL FFmpeg built with libx264 + libx265.
  static let gpl = Self(
    summary: String(
      localized: """
        SubTrack bundles FFmpeg built with libx264 and libx265, licensed under the GNU General \
        Public License, version 2 or later (GPL v2+). This software uses code of the FFmpeg \
        project licensed under the GPLv2+.
        """
    ),
    licenseTitle: String(localized: "FFmpeg — GPL v2+ (with libx264 + libx265)"),
    licenseBody: String(
      localized: """
        The FFmpeg build bundled with this copy of SubTrack is configured with libx264 and \
        libx265, which are licensed under the GNU General Public License (GPL) version 2 or later. \
        The combined work is therefore distributed under the GPL v2+.

        This software uses code of the FFmpeg project licensed under the GPLv2+.

        FFmpeg — Copyright © 2000–2024 the FFmpeg developers.
        x264 — Copyright © 2003–2024 the x264 project.
        x265 — Copyright © 2013–2024 MulticoreWare, Inc.

        The full text of the GNU GPL v2 is available at \
        https://www.gnu.org/licenses/old-licenses/gpl-2.0.html. FFmpeg source and license \
        information are available at https://www.ffmpeg.org.
        """
    )
  )

  /// A short paragraph shown inline in the About window.
  var summary: String
  /// The heading for the full-text button/sheet.
  var licenseTitle: String
  /// The longer, scrollable license and attribution text.
  var licenseBody: String

  /// Selects the acknowledgement for a build from its codec-set flag.
  static func forBuild(fullCodecSet: Bool) -> Self {
    fullCodecSet ? .gpl : .lgpl
  }
}

/// Identifying details read from the running app's bundle.
struct AppInfo: Sendable, Equatable {

  static var current: Self {
    let info = Bundle.main.infoDictionary ?? [:]
    func string(_ key: String) -> String? {
      (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    return Self(
      name: string("CFBundleName") ?? "SubTrack",
      version: string("CFBundleShortVersionString") ?? "—",
      build: string("CFBundleVersion") ?? "—",
      copyright: string("NSHumanReadableCopyright") ?? fallbackCopyright
    )
  }

  /**
   The notice shown when the bundle carries no `NSHumanReadableCopyright`,
   naming the current year so a build that ships without one never advertises
   a year that has already passed.
   */
  private static var fallbackCopyright: String {
    let year = Calendar.current.component(.year, from: .now)
    return String(localized: "Copyright © \(year, format: .number.grouping(.never))")
  }

  var name: String
  var version: String
  var build: String
  var copyright: String
}
