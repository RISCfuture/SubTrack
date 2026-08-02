# Credits

SubTrack itself is licensed under the [GNU General Public License, version 2 or
later](LICENSE). The components below carry their own terms. The same notices appear in
the app's About window, which shows the set applying to the edition you're running.

## FFmpeg

Each edition bundles a different FFmpeg build, and they are licensed differently.

### Mac App Store edition — LGPL v2.1+

SubTrack bundles FFmpeg, built under the GNU Lesser General Public License, version 2.1
or later (LGPL v2.1+), with no GPL-licensed components — it contains no libx264, libx265,
or other GPL libraries. Video encoding uses Apple VideoToolbox. This software uses
libraries from the FFmpeg project under the LGPLv2.1.

The full text of the GNU LGPL v2.1 is available at
<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>.

### Direct download edition — GPL v2+

SubTrack bundles FFmpeg built with libx264 and libx265, which are licensed under the GNU
General Public License, version 2 or later (GPL v2+). The combined work is therefore
distributed under the GPL v2+. This software uses code of the FFmpeg project licensed
under the GPLv2+.

The full text of the GNU GPL v2 is available at
<https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>.

### Copyright and source

- FFmpeg — Copyright © 2000–2026 the FFmpeg developers. <https://www.ffmpeg.org>
- x264 — Copyright © 2003–2024 the x264 project. <https://www.videolan.org/developers/x264.html>
- x265 — Copyright © 2013–2024 MulticoreWare, Inc. <https://www.videolan.org/developers/x265.html>
- libaom (AV1) — Copyright © 2016 Alliance for Open Media. BSD 2-Clause, with the
  Alliance for Open Media Patent License 1.0. Bundled in both editions, since its terms
  suit the LGPL build as well. <https://aomedia.googlesource.com/aom/>

`Scripts/build-ffmpeg.sh` pins the exact version of every one of these and builds them
from source. Running it reproduces the bundled binaries. The corresponding sources are
also attached to each GitHub release of the download edition.

## Swift packages

- [DockProgress](https://github.com/sindresorhus/DockProgress) by Sindre Sorhus — MIT.
- [GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker) — MIT. Used by
  the download edition only. It depends in turn on
  [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui),
  [NetworkImage](https://github.com/gonzalezreal/NetworkImage),
  [swift-cmark](https://github.com/swiftlang/swift-cmark), and
  [swift-log](https://github.com/apple/swift-log).
- [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) — MIT.
- [XCUITestKit](https://github.com/RISCfuture/XCUITestKit) — MIT. Test-only; not shipped
  in either app.
