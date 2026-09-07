# TODO

## An affordance for errors nobody is told about

SubTrack has no way to tell the user that something went wrong outside the
queue. Every failure it reports is a property of a queue item — a row turns
red, its subtitle carries the message, and the Activity Log spells it out. That
covers everything the encoder can do wrong, and nothing else.

The single `.alert` in the app is the Save Preset naming prompt. It is not an
error surface.

### What currently goes unreported

`QueuePersistenceController` raises `PersistenceError` twice, and both land in
`logger.error` and stop there:

- `saveFailed` — the queue's state could not be written. The user finds out by
  quitting and reopening to a workspace missing whatever it was that failed to
  save. This is the one that matters: it is silent data loss, and the window
  goes on looking correct until the moment it is too late.
- `fetchFailed` — stored data could not be read at launch, so the workspace
  comes up emptier than the user left it, presented as though that were normal.

Neither is user-actionable in the sense of "here is the button that fixes it",
which is why `PersistenceError` deliberately carries no `recoverySuggestion`.
That argued for logging rather than prompting, and it is why this was left as
it is. But "you cannot fix it" is not the same as "you should not be told":
the person who knows a save failed can copy their work out, or stop adding to
a queue that is not being recorded. The person who is not told cannot.

`CloudSyncMonitor` and `PresetStore` should be audited on the same question
before this is designed — this list is what the audit of 2026-09-07 found in
the queue's own persistence, not a claim that nothing else is silent.

### The shape it should take

A failed autosave is a **condition, not an event**. It persists until a write
succeeds, it can repeat every few seconds, and it is not something the user
did. That rules out a modal alert: an alert per failed write is intolerable,
and an alert for the first failure only is worse, because dismissing it hides a
problem that is still true.

Proposed: a persistent indicator in the queue window's status bar, at the
trailing edge opposite the item summary.

- Hidden entirely while writes are succeeding. This costs nothing in the normal
  case, which is the overwhelming majority of the time.
- When a write has failed and not since succeeded, an `exclamationmark.triangle`
  in `.red` — the tier the severity policy already assigns to "cannot produce
  what you asked for" — with a short label such as "Not saving".
- Its tooltip carries the `userMessage`, which is where `failureReason` and any
  `recoverySuggestion` already compose.
- Clicking it opens the Activity Log, which is where a fuller account belongs
  and which no longer truncates.
- It clears itself the moment a write succeeds, so a transient failure during a
  volume hiccup does not leave a scare on screen once the volume returns.

### Work involved

1. Somewhere to hold the condition. `QueuePersistenceController` knows when a
   write fails and when the next one succeeds; the natural home is an
   observable `lastPersistenceFailure: PersistenceError?` on it, cleared on the
   next success, surfaced through `Workspace` the way run state already is.
2. A `PersistenceFailureIndicator` subview in `QueueStatusBar`, following the
   severity policy in `NameCell` and `ActivityLogView` rather than inventing a
   third vocabulary. It needs an accessibility label, not just a glyph.
3. A UI test driving a seeded persistence failure through the harness. This
   needs a new `UITEST_*` switch — the harness stubs the conversion engine but
   not the store, so there is currently no way to make a write fail on demand.
4. Unit coverage for the set-and-clear transition, which is the part with
   actual logic: it must not latch on after a later write succeeds, and it must
   not flicker on a retry that immediately succeeds.

### Explicitly out of scope

- A general error-presentation framework. One condition needs a surface; an
  architecture for every future error does not need designing before it.
- Retrying failed writes automatically. Worth considering, but it is a
  behaviour change to persistence and independent of telling the user.

### Why it is not done

Raised during the status-message audit of 2026-09-07 and deliberately deferred:
the rest of that audit corrected miscategorised and unreachable messages, which
were defects. This one is a missing affordance, and choosing its shape is a
design decision about the app's error vocabulary rather than a correction to
something already wrong.
