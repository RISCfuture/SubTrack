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
- Queue columns can be hidden. Right-click the table header to drop the metrics
  you don't read; the width goes back to Name, which is the column with
  variable-length content.
- Undo takes back the destructive queue edits. Remove Selected, Clear Completed,
  and drag-reordering are all undoable, and an item comes back with the track
  overrides you set by hand rather than needing a re-probe.

### Changed

- Output is staged and moved into place only once a run has exited cleanly and
  been verified. A cancel, a crash, or a failed encode now leaves the
  destination untouched, where before it could leave a truncated file under the
  finished output name — and re-running over a good file no longer destroys it
  before there is anything to replace it with.
- Running out of room on the output volume is reported as such, before `ffmpeg`
  starts, instead of arriving as `ffmpeg exited with code 1`.
- Dragging a queue row shows an insertion line rather than highlighting the row
  under the cursor, and a row can be dropped at the end of the queue.
- Removing an item that is encoding is called "Cancel and Remove", because that
  is what it does. The plain name said only that rows would go away, and the
  encode it killed is the one part undo cannot give back.
- An item whose rules keep none of the source's audio is marked with an info
  button after its name, explained in a tooltip, rather than a caution triangle
  before it.
- Every error state is tinted, and tinted alike in the queue and the Activity
  Log. A failed run previously carried no colour at all in the queue, and an
  encode the build cannot perform changed severity depending on which window
  you looked at.

## 1.0

- First release.
