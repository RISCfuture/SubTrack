# TODO

Two Apple APIs worth adopting, ordered by how much they fix something that is
actually broken today against what they cost to build. Each entry records the
gotcha that a first attempt would otherwise walk into.

## 1. Let the user hide queue table columns

`TableColumnCustomization` with
`Table(of:selection:columnCustomization:columns:rows:)` and
`.customizationID(_:)` — macOS 14.0, not deprecated, and `Codable & Sendable`.

Five of the seven columns in `QueueTableView` are narrow capped metrics
(28/70/80/85/95pt against Name's ideal 300), and the file's own comment already
admits Name is starved. Hiding Input Tracks, Input Size, and Destination hands
roughly 315pt back to Name when the inspector is open.

**Do not add the `sortOrder:` pairing.** Queue order *is* execution order, and
the `rows:` builder does manual drag reordering — `.draggable` gated on
`status.isReorderable`, `.dropDestination` calling `moveItems(_:before:)`. A
sort binding would show rows in an order that doesn't match what runs next, and
dropping "before" a row inside a sorted view is incoherent. The doc comment
calling the table sortable is describing drag-reordering; reword it.

**Persist it through the repo's own store pattern.** `UIState` is documented as
transient per-launch window state; `@AppStorage` cannot hold a
`TableColumnCustomization` at all, since `Codable` isn't sufficient and it
needs a primitive or a `String`/`Int`-backed `RawRepresentable`; and putting a
global window preference into the CloudKit-synced workspace record would scope
it per-queue *and* sync it, both wrong. The right home is a new
`@MainActor @Observable` store in `Persistence/Stores/` over an injectable
`UserDefaults`, mirroring `OutputDestinationStore`.

Give the leading status column no `customizationID`, so it can never be hidden
or show up as a blank menu entry, and apply
`.disabledCustomizationBehavior(.visibility)` to Name. Use stable, non-localized
ids — never derive one from a `LocalizedStringResource`, since they have to
survive app updates. Leave `ActivityLogView` alone; three columns have no width
pressure.

Identical in both editions; no entitlement, no file access.

## 2. Undo for the destructive queue edits

`EnvironmentValues.undoManager` — macOS 10.15, not deprecated. SwiftUI's
`CommandGroupPlacement.undoRedo` already supplies the Edit-menu items, so
there is no menu plumbing to write once a manager is reachable.

Three edits destroy work today with no way back: Remove Selected, Clear
Completed, and drag-reordering. Remove Selected is bound to a bare Delete with
no confirmation, which is a cheap keystroke with an expensive and silent
consequence — and one that re-adding the files does not undo. A `QueueItem`
carries its own security-scoped bookmarks to source and output folder plus the
per-track and output-name overrides set by hand in the inspector, so re-adding
means re-ingesting and re-probing every file through ffprobe, and the overrides
are simply gone.

That same fact makes undo unusually cheap here: `QueueItem` is a `final class`,
so the undo closure retains the removed items and puts them back. No
serialization, no re-probing, no bookmark re-resolution, and the overrides
survive because they were never rebuilt.

**`\.undoManager` is nil inside `Commands` and `CommandMenu`, which is exactly
where all three call sites live.** Measured against this app's scene shape — a
`Window` plus `.commands` — a read inside a command button is nil, while a view
inside the window gets a manager identical to `NSWindow.undoManager`. Registered
naively from `SubTrackCommands`, the feature silently does nothing at all. The
prerequisite is a `weak var undoManager: UndoManager?` on `UIState`, populated
from `QueueWindowView` via `@Environment(\.undoManager)` and
`.onChange(of:initial: true)`, with the commands registering through
`environment.ui.undoManager`.

Scope it to item removal, `clearCompleted`, and reorder in `QueueCoordinator`.
Note that `moveItems(_:before:)` is **not** self-inverse — it filters to
reorderable items and bails on unknown targets — so its undo has to restore a
full prior `[UUID]` order snapshot rather than replay the move backwards.
Decide and document that an item removed mid-run comes back settled, not
running, with no partial output restored.

**Leave queue deletion out.** `Workspace.deleteQueue` tears down the
coordinator, unregisters it from the governor, drops monitors, reindexes, and
auto-seeds a replacement "Queue 1"; undoing that means rebuilding through
`coordinatorFactory` with the original UUID, re-hydrating items down the
bookmark-preserving path, deleting the seeded replacement, and re-driving
`persistAll()` — as much work as the rest of undo combined, and
`requestQueueDeletion` already confirms the case that matters.

Swift 6 is not an obstacle: `registerUndo(withTarget:handler:)` is
`NS_SWIFT_UI_ACTOR`-annotated and typechecks against a `@MainActor final class`
under complete concurrency checking with no `assumeIsolated`.

This is the largest item here, and it is not the cheap fix for the bare-Delete
binding — a confirmation, or dropping `.keyboardShortcut(.delete, modifiers:
[])`, costs a fraction of it. Build undo because it is correct Mac behavior
across all three edits.
