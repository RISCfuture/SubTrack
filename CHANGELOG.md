# Changelog

Release notes for SubTrack. The version headings are what
`Scripts/release-notes.sh` reads, and what the Release workflow attaches to a
GitHub release — so a heading is `## <version>`, matching the tag exactly.

## Unreleased

### New

- Encoding holds off idle sleep. An overnight batch now runs to the end instead
  of stopping when the Mac sleeps.
- A notification when a queue finishes, so a run measured in tens of minutes is
  one you can walk away from.

### Changed

- Output is staged and moved into place only once a run has exited cleanly and
  been verified. A cancel, a crash, or a failed encode now leaves the
  destination untouched, where before it could leave a truncated file under the
  finished output name — and re-running over a good file no longer destroys it
  before there is anything to replace it with.
- Running out of room on the output volume is reported as such, before `ffmpeg`
  starts, instead of arriving as `ffmpeg exited with code 1`.

## 1.0

- First release.
