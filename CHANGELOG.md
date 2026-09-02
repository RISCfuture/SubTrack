# Changelog

Release notes for SubTrack. The version headings are what
`Scripts/release-notes.sh` reads, and what the Release workflow attaches to a
GitHub release — so a heading is `## <version>`, matching the tag exactly.

## Unreleased

### New

- Encoding holds off idle sleep. An overnight batch now runs to the end instead
  of stopping when the Mac sleeps.

### Changed

- Output is staged and moved into place only once a run has exited cleanly and
  been verified. A cancel, a crash, or a failed encode now leaves the
  destination untouched, where before it could leave a truncated file under the
  finished output name — and re-running over a good file no longer destroys it
  before there is anything to replace it with.

## 1.0

- First release.
