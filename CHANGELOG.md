# Changelog

Release notes for SubTrack. The version headings are what
`Scripts/release-notes.sh` reads, and what the Release workflow attaches to a
GitHub release — so a heading is `## <version>`, matching the tag exactly.

## 1.2.1

### Fixed

- An MP4 whose subtitles are kept slims again. SubTrack converted them to a
  format MP4 cannot hold, so FFmpeg refused to write the file and the run failed
  with exit code 234. MP4 subtitles are now copied as they are, and converted
  only when the output is MKV.
- A Dolby Vision MP4 keeps its Dolby Vision. The slimmed copy came out with only
  the HDR10 picture underneath it, so it played as HDR10 on a Dolby Vision
  display.

## 1.2

### Requirements

- SubTrack now requires macOS 27, and runs on Apple silicon only. A Mac on
  macOS 26, or any Intel Mac, cannot run this version; 1.1 is the last release
  it can.

### Fixed

- Updating no longer fails for anyone whose Applications folder sits behind a
  path carrying an apostrophe or a quote. The download edition could ask for
  permission, copy the new version, and then be unable to relaunch it.
- The inspector's menus mark the entry in force again. On macOS 27 the
  checkmark beside the active preset and beside the chosen transcode target
  went undrawn, so both menus opened looking as though nothing had been picked.
- SubTrack is an Apple-silicon app, and now says so. The Intel slice it shipped
  could not run the bundled FFmpeg, which is built for Apple silicon only, so
  on an Intel Mac SubTrack launched and then failed at the one thing it exists
  to do.

### Changed

- Cancelling a run asks FFmpeg to stop, gives it a few seconds to close the
  file it has open, and kills it if it has not gone by then. A single request to
  stop can be ignored by an encode that has wedged, which left the run showing
  as cancelling with FFmpeg still working; the cancel now takes effect either
  way, and the cancelled output is discarded only once nothing is still writing
  into it.

## 1.1

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
- SubTrack says so when it cannot record your work. A queue whose changes fail
  to save now raises a "Not saving" indicator in the status bar for as long as
  it stays true, and clicking it opens the Activity Log, which explains what
  went wrong in full.
- The Activity Log is a real log. It records each run starting and what it came
  to, and everything that went wrong in between — a file that failed, a source
  that went away, a transcode the current FFmpeg can't perform, a store that
  stopped saving — each with the time it happened, across every queue at once.
- What it leaves out is the point of it: a file that inspects, encodes and
  finishes writes no line, so a clean overnight run of three hundred files is
  two lines rather than six hundred. A queue that has had no trouble says
  "Nothing to report", and the log empties when you quit.

### Fixed

- A store that briefly could not be read is no longer mistaken for an empty
  one. It could cause the starter presets to be written on top of presets you
  already had, an edited preset to be saved as a second copy of itself, your
  preset list to blank out, and a queue to be stored twice over and come back
  as two identical rows in the sidebar.
- Settling a file into the state it was already in no longer counts as a change.
  A large queue is no longer rewritten to disk in full on every launch and every
  write to a source's folder.

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
- The Activity Log shows a message in full, wrapping rather than truncating. A
  failure carries its recovery suggestion at the end — including where a
  finished file was left when it could not be moved into place — which was
  exactly the part being cut off.
- The sidebar's warning triangle is red for a queue holding a run that failed
  or a source that has gone, and stays orange for one whose plan the current
  FFmpeg cannot encode.

## 1.0

- First release.
