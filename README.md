# SubTrack

[![Tests](https://github.com/RISCfuture/SubTrack/actions/workflows/test.yml/badge.svg)](https://github.com/RISCfuture/SubTrack/actions/workflows/test.yml)
[![Linters](https://github.com/RISCfuture/SubTrack/actions/workflows/lint.yml/badge.svg)](https://github.com/RISCfuture/SubTrack/actions/workflows/lint.yml)
[![Periphery](https://github.com/RISCfuture/SubTrack/actions/workflows/periphery.yml/badge.svg)](https://github.com/RISCfuture/SubTrack/actions/workflows/periphery.yml)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://developer.apple.com/)
[![License: GPL v2+](https://img.shields.io/badge/license-GPLv2%2B-blue.svg)](LICENSE)

SubTrack is a macOS app that strips unwanted audio and subtitle tracks out of video
files by copying, not re-encoding — so a two-hour Blu-ray rip slims down in seconds,
with no quality loss.

<https://riscfuture.github.io/SubTrack/>

Get it from the
[Mac App Store](https://apps.apple.com/us/app/subtrack-trim-video-files/id6794950780), or
[download it directly](https://github.com/RISCfuture/SubTrack/releases/latest).

## What It Is

A Blu-ray or UHD remux often carries a dozen tracks: eight dubs you don't speak, five
subtitle languages you don't read, and a commentary track you'll never play. They're
most of the file size and none of the value.

SubTrack drops them. Everything you keep is stream-copied into a new file, bit for bit —
same container, same picture, a fraction of the size.

- **Rules, not busywork.** Choose which languages to keep, whether commentary and
  alternate mixes count, and what to do with untagged tracks. The same rules apply to
  every file in the queue.
- **See the plan before it runs.** The inspector lists every track and exactly what will
  happen to it — keep, drop, or convert — and any of it can be overridden per file.
- **Transcoding only when it must.** Name the codecs you're happy to keep. If a kept
  track isn't one of them, SubTrack converts just that track, and says so up front.
- **Presets that follow you.** Saved rule sets sync between your Macs through your own
  iCloud account.
- **As many queues as you like**, each with its own files, rules, preset, and output
  folder, restored exactly as you left them.
- **FFmpeg included.** A signed, self-contained build ships inside the app.

SubTrack is a track slimmer, not a transcoder. Transcoding is an automatic fallback for
the rare kept track in an unacceptable codec — there are deliberately no quality, preset,
or bitrate knobs. That's HandBrake's job.

## Editions

Two app targets build from this one project, and both produce `SubTrack.app`:

| | **SubTrack (MAS)** | **SubTrack (download)** |
| --- | --- | --- |
| Distribution | [Mac App Store](https://apps.apple.com/us/app/subtrack-trim-video-files/id6794950780) | [Developer-ID notarized](https://github.com/RISCfuture/SubTrack/releases/latest) |
| Bundle ID | `codes.tim.SubTrack-MAS` | `codes.tim.SubTrack-download` |
| Bundled FFmpeg | LGPL v2.1+, VideoToolbox only | GPL v2+, with libx264 and libx265 |
| Custom FFmpeg location | — | ✓ |
| `subtrack` CLI installer | — | ✓ |
| In-app update checks | — (the store handles it) | ✓ |

The three differences in the last rows are App Store policy, not capability. `FeatureFlags`
in `SubTrack Common/UI/App/AppEnvironment.swift` carries `isAppStoreBuild`, and every gated
control shows a help link to the download edition instead. Both editions share the iCloud
container, so presets sync between them.

## Requirements

SubTrack is written in Swift 6 and requires macOS 26.4.

## Development

### Bundled FFmpeg

The app bundles its own FFmpeg, and the binaries are **not** checked in. Each app target's
**Build Bundled ffmpeg** phase builds the variant that edition ships before the phase that
copies it in, so a fresh clone needs no preparation — but the first build of a checkout
spends a long time in that phase, compiling from pinned upstream sources over the network.
Run either variant ahead of time to get that out of the way, or to rebuild after deleting
`Vendor/`:

```sh
Scripts/build-ffmpeg.sh lgpl   # for SubTrack (MAS)
Scripts/build-ffmpeg.sh full   # for SubTrack (download)
```

Each produces a static, self-contained, arm64 `ffmpeg` and `ffprobe` in
`Vendor/ffmpeg-<variant>/`, depending only on macOS system frameworks. Every version is
pinned in the script; nothing floats to "latest". `Scripts/upgrade-ffmpeg.sh` re-pins,
rebuilds, and verifies both variants.

### Help book

Both editions ship the Apple Help book in `Help/SubTrack.help`, staged into the app by the
**Build Help Book** phase and illustrated by screenshots taken from the running app.
[`Help/README.md`](Help/README.md) covers writing a page, the anchor check that fails the
build, the `fastlane mac help_screenshots` lane, and the `helpd` cache that makes an edit
look like it never took.

### Targets

- **SubTrack Common** — framework holding the shared UI and model layer.
- **Engine** — the Foundation-only conversion engine, compiled into both the framework
  and the CLI.
- **SubTrack (MAS)** / **SubTrack (download)** — the two app shells.
- **subtrack** — the command-line tool, embedded in both apps for optional installation.
- **SubTrack CommonTests**, **SubTrackCLITests**, **SubTrack-downloadUITests**,
  **SubTrack-MASUITests** — the test targets.

### Schemes

Six shared schemes. Which you can run depends on whether `Vendor/` is populated:

| Scheme | Needs FFmpeg built? |
| --- | --- |
| `SubTrack Common Tests` | no — host-less, builds only the test bundle |
| `SubTrack CLI Tests` | yes — the tests run the real `Vendor/ffmpeg-full/ffmpeg` |
| `SubTrack (download)` / `SubTrack (MAS)` | yes |
| `SubTrack (download) UITests` / `SubTrack (MAS) UITests` | yes |

Both app targets emit `SubTrack.app` into the same build directory, so **never run two
app or UI-test schemes concurrently** — the second build clobbers the first's bundle
mid-run. Build a specific edition into its own `CONFIGURATION_BUILD_DIR` when you need to
inspect its bundle.

The UI test suites run against a stub engine gated behind a `-uiTesting` launch argument,
so they never invoke FFmpeg, and are built on
[XCUITestKit](https://github.com/RISCfuture/XCUITestKit).

### Crash reporting

[Sentry](https://sentry.io) is wired into both editions. Debug builds and test runs
discard their events before transmission.

### Releasing

Pushing a version tag (`1.0`, `1.1.2` — no `v` prefix, because the update checker compares
tags against `CFBundleShortVersionString`) archives both editions, uploads the App Store
build to App Store Connect, and publishes a GitHub release with the notarized disk image.

Signing credentials come from the private `RISCfuture/certificates` repository via
[fastlane match](https://docs.fastlane.tools/actions/match/). Locally, copy
`fastlane/.env.example` to `fastlane/.env` and fill it in. On CI the same names arrive as
repository secrets: `CERTIFICATES_TOKEN`, `MATCH_PASSWORD`, and `SENTRY_AUTH_TOKEN`.

## License

SubTrack is licensed under the [GNU General Public License, version 2 or later](LICENSE).

The FFmpeg binaries the app bundles carry their own terms — LGPL v2.1+ for the App Store
edition, GPL v2+ for the download edition, which is built with libx264 and libx265. See
[CREDITS.md](CREDITS.md), and the About window inside the app, for the full notices.

Being the sole copyright holder is what makes distributing a GPL-licensed build through
the Mac App Store workable, since the store's terms and the GPL's section 6 otherwise
pull against each other. Outside contributions would complicate that, so please open an
issue to discuss before sending a pull request.
