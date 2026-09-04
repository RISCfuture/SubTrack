public import Foundation
import os

/**
 Drives the conversion queue: probes added files, schedules runs up to a
 concurrency limit, tracks per-item and overall progress, and handles
 cancellation and missing sources. Observable so the UI binds directly.
 */
@MainActor
@Observable
public final class QueueCoordinator: Identifiable {
  /**
   How many files to add between yields to the run loop — small enough that
   the window keeps drawing, large enough that yielding doesn't dominate.
   */
  private static let ingestChunkSize = 20

  private static let log = Logger(subsystem: "SubTrack", category: "QueueCoordinator")

  /// The stable identity of this queue, shared with its persistence record.
  public let id: UUID

  /// The queue's user-facing name.
  public var name: String

  /// The queue's position in the workspace sidebar.
  public var sortIndex: Int

  /// This queue's own keep-rules, active preset, and output destination.
  public let settings: QueueSettings

  /// The queue's items, in run order.
  public private(set) var items: [QueueItem] = []

  /// The in-flight ingest's progress, or `nil` when none is running.
  public private(set) var ingestProgress: IngestProgress?

  /// The current table selection (item IDs).
  public var selection: Set<UUID> = []

  /**
   The selected `ffmpeg` build's encoder capabilities, driving item
   compatibility. Permissive until the first probe completes, so nothing is
   falsely flagged at launch.
   */
  public private(set) var encoderCapabilities: EncoderCapabilities = .full

  #if DEBUG
    /**
     Pins the capabilities to a fixed build for a UI test, so the compatibility
     axis can be driven without a real `ffmpeg` to probe. Setting it applies
     immediately and outlasts any later probe; `nil` restores the probed value.
     */
    public var encoderCapabilitiesOverride: EncoderCapabilities? {
      didSet {
        guard let encoderCapabilitiesOverride else { return }
        encoderCapabilities = encoderCapabilitiesOverride
        revalidateAllCompatibility()
      }
    }
  #endif

  /**
   Fired on structural and settled changes that should be written through to
   persistence — item add/remove/reorder and settled status transitions —
   never on transient `probing`/`running` states or live `progress` updates.
   */
  public var onPersistableChange: @MainActor () -> Void = {}

  /**
   Fired whenever ``hasEncodeWorkInFlight`` may have changed, so a ``Workspace``
   can tell when the app as a whole starts and stops encoding. Fired on the
   possibility of a change rather than on a confirmed one — the reader compares
   against its own last answer.
   */
  public var onEncodeActivityChanged: @MainActor () -> Void = {}

  /**
   Fired as each run settles, with what that run came to. Only `runItem(_:)`
   reaches this, so a probe, a re-scan, or a revalidation settling an item never
   looks like a run — which is what makes a rolled-up summary count only the
   files a run actually touched.
   */
  public var onRunSettled: @MainActor (QueueRunOutcome) -> Void = { _ in }

  /**
   The undo manager of the window this queue is shown in, or `nil` when it is
   shown in none — every preview, and every test that doesn't ask for undo,
   where the destructive edits here simply aren't undoable. Set by
   ``Workspace``, which hands the same manager to every queue it owns, so a
   removal registers its undo wherever it was asked for: the Queue menu, a
   row's context menu, or a drag.

   Weak, because the window owns it. Its registered actions hold this
   coordinator *unowned*, which is why ``teardown()`` withdraws them.
   */
  @ObservationIgnored public weak var undoManager: UndoManager?

  /**
   Fired as an undo or redo lands, so a ``Workspace`` can bring the affected
   queue forward. The undo stack is window-wide but a queue is not: without
   this, taking back a removal made in one queue would refill a queue the user
   isn't looking at.
   */
  public var onUndoAppliedChange: @MainActor () -> Void = {}

  private let engine: any ConversionEngineProtocol
  private let governor: EncodeGovernor
  private let makeBookmark: @MainActor (URL) -> Data?
  private let beginSourceAccess: @MainActor (QueueItem) -> ScopedAccess
  private let beginOutputFolderAccess: @MainActor (QueueItem) -> ScopedAccess
  private let probeCapabilities: @Sendable () async -> EncoderCapabilities?
  private let availableCapacity: @MainActor (URL) -> Int?

  private var runTasks: [UUID: Task<Void, Never>] = [:]
  private var pending: [UUID] = []
  private var monitors: [UUID: SourceFileMonitor] = [:]

  /// Probes waiting for a slot, drained by ``pumpProbes()``.
  private var pendingProbes: [PendingProbe] = []

  /**
   Items being probed right now, bounding how many security scopes are held
   at once.
   */
  private var activeProbes: Set<UUID> = []

  /**
   Creates a queue wired to the shared engine and governor its workspace owns.

   - Parameter id: The queue's stable identity, shared with its persistence
     record.
   - Parameter name: The queue's user-facing name.
   - Parameter sortIndex: The queue's position in the workspace sidebar.
   - Parameter engine: Performs the probes and encodes this queue schedules.
   - Parameter governor: The app-wide gate on how many encodes run at once, so
     the limit spans every queue rather than this one.
   - Parameter settings: This queue's own keep-rules, active preset, name
     format, and output destination.
   - Parameter makeBookmark: Mints a security-scoped bookmark to a URL while a
     transient grant covering it is still live.
   - Parameter beginSourceAccess: Opens security-scoped read access to an item's
     source for the length of a probe or run.
   - Parameter beginOutputFolderAccess: Opens security-scoped write access to
     the folder an item's output is written into.
   - Parameter probeCapabilities: Reads what the currently-resolved `ffmpeg` can
     encode, or `nil` when it can't be asked.
   - Parameter availableCapacity: Reads how much room a folder's volume has for
     a file the user is waiting on, or `nil` when the volume won't say.
   - Parameter onPersistableChange: Fired on the structural and settled changes
     that should be written through to persistence.
   */
  public init(
    id: UUID = UUID(),
    name: String = "",
    sortIndex: Int = 0,
    engine: any ConversionEngineProtocol,
    governor: EncodeGovernor = EncodeGovernor(),
    settings: QueueSettings = QueueSettings(),
    makeBookmark: @escaping @MainActor (URL) -> Data? = { _ in nil },
    beginSourceAccess: @escaping @MainActor (QueueItem) -> ScopedAccess = { _ in .none },
    beginOutputFolderAccess: @escaping @MainActor (QueueItem) -> ScopedAccess = { _ in .none },
    probeCapabilities: @escaping @Sendable () async -> EncoderCapabilities? = { nil },
    availableCapacity: @escaping @MainActor (URL) -> Int? = \.availableCapacityForImportantUsage,
    onPersistableChange: @escaping @MainActor () -> Void = {}
  ) {
    self.id = id
    self.name = name
    self.sortIndex = sortIndex
    self.engine = engine
    self.governor = governor
    self.settings = settings
    self.makeBookmark = makeBookmark
    self.beginSourceAccess = beginSourceAccess
    self.beginOutputFolderAccess = beginOutputFolderAccess
    self.probeCapabilities = probeCapabilities
    self.availableCapacity = availableCapacity
    self.onPersistableChange = onPersistableChange
    settings.onChange = { [weak self] in self?.settingsDidChange() }
    governor.register(id) { [weak self] in self?.pump() }
  }

  /**
   Restates every pending item's output path, revalidates compatibility against
   the queue's current rules, and writes the settings change through. The single
   hook for a rules-field edit, preset switch, name-format edit, or destination
   change on this queue.
   */
  public func settingsDidChange() {
    refreshOutputNames()
    revalidateAllCompatibility()
    onPersistableChange()
  }

  /**
   Cancels in-flight work, detaches from the governor, and withdraws this
   queue's undo actions. Call when the queue is deleted so its pump callback
   and monitors don't linger.

   Withdrawing matters for more than tidiness: the undo stack holds this
   coordinator unowned and its removed items strongly, so actions left behind
   would resurrect a queue nobody can see, write it through to persistence,
   and eventually invoke against a released target.
   */
  public func teardown() {
    cancelAll()
    governor.unregister(id)
    monitors.removeAll()
    undoManager?.removeAllActions(withTarget: self)
  }

  // MARK: - Mutating the queue

  /**
   Expands folders/URLs to movie files and adds them (for drag-and-drop, the
   open panel, and Open). Reports progress through ``ingestProgress`` so a
   large folder shows a sheet rather than freezing the window.
   */
  public func ingest(_ urls: [URL]) {
    Task { await ingestAsync(urls) }
  }

  /**
   The awaitable body of ``ingest(_:)``, for callers that need to know when
   the ingest has finished.
   */
  public func ingestAsync(_ urls: [URL]) async {
    let progress = IngestProgress()
    ingestProgress = progress
    defer { ingestProgress = nil }

    progress.beginScanning()
    let found = await Task.detached {
      MovieFileFinder.expand(urls) { count in
        Task { @MainActor in progress.recordScanned(count) }
      }
    }.value
    guard !progress.isCancelled else { return }

    progress.beginAdding(total: found.count)
    await add(found, reporting: progress)
  }

  /**
   Adds source files (skipping duplicates) and queues each for probing.

   Both of an item's bookmarks are captured here, while the transient sandbox
   grant from the drop, open panel, or folder enumeration is still live —
   neither can be minted later, so an item added without them can never write.

   The loop yields every `ingestChunkSize` files so the window keeps drawing
   while a season's worth of bookmarks are minted. Cancelling stops the loop
   but keeps the rows already added: they are valid entries, and discarding
   them would throw away bookmarks that cannot be minted again.
   */
  public func add(_ urls: [URL], reporting progress: IngestProgress? = nil) async {
    var existing = Set(items.map(\.sourceURL))
    for (offset, url) in urls.enumerated() {
      if progress?.isCancelled == true { break }
      progress?.recordAdded(url.lastPathComponent)
      guard existing.insert(url).inserted else { continue }
      let item = makeItem(for: url)
      items.append(item)
      startMonitoring(item)
      enqueueProbe(item)
      if (offset + 1).isMultiple(of: Self.ingestChunkSize) {
        await Task.yield()
        // A second ingest can add rows while this one is suspended, so the set
        // of sources already queued is re-read before the next chunk trusts it.
        existing.formUnion(items.map(\.sourceURL))
      }
    }
    onPersistableChange()
  }

  /// Builds a queue item for `url`, capturing its bookmarks and size.
  private func makeItem(for url: URL) -> QueueItem {
    let output = outputURL(for: url, position: items.count + 1, customName: nil)
    let item = QueueItem(sourceURL: url, outputURL: output)
    item.sourceBookmark = makeBookmark(url)
    if !settings.destination.covers(output) {
      item.outputFolderBookmark = makeBookmark(output.deletingLastPathComponent())
    }
    item.sourceByteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    return item
  }

  /**
   Rebuilds this queue from its persisted `snapshot` at launch: restores the
   queue's own rules, active preset, and destination, then its items — without
   re-deriving bookmarks (which would fail with no active transient grant).
   The persisted bookmark bytes are set directly, transient states arrive
   already collapsed to `ready`, and settled states keep their reason. Sources
   begin monitoring so a vanished file flips to `missing`; call
   ``postHydrationRefresh()`` afterward to re-probe and revalidate.
   */
  public func hydrate(_ snapshot: QueueSnapshot) {
    settings.hydrate(snapshot)
    for snapshot in snapshot.items.sorted(by: { $0.sortIndex < $1.sortIndex }) {
      let item = QueueItem(
        sourceURL: URL(filePath: snapshot.sourcePath),
        outputURL: URL(filePath: snapshot.outputPath)
      )
      item.customName = snapshot.customName
      item.sourceBookmark = snapshot.sourceBookmark
      item.outputFolderBookmark = snapshot.outputFolderBookmark
      item.selection = snapshot.selection
      item.sourceByteCount = snapshot.sourceByteCount
      item.outputByteCount = snapshot.outputByteCount
      item.tracksRemoved = snapshot.tracksRemoved
      item.lastError = snapshot.lastError
      item.status = snapshot.status.state(reason: snapshot.lastError)
      items.append(item)
      startMonitoring(item)
    }
  }

  /**
   Kicks the post-launch reconciliation for hydrated items: re-probes `ready`
   items (which flips a vanished source to `missing`) and revalidates every
   item's compatibility against the currently-resolved `ffmpeg`.
   */
  public func postHydrationRefresh() {
    for item in items where item.status == .ready { enqueueProbe(item) }
    ffmpegLocationChanged()
  }

  /// Removes items, cancelling any in-flight work. Undoable.
  public func remove(_ ids: Set<UUID>) {
    removeItems(ids, named: .removeFromQueue)
  }

  /// Removes all finished items. Undoable, as a single edit.
  public func clearCompleted() {
    removeItems(Set(items.filter { $0.status == .done }.map(\.id)), named: .clearCompleted)
  }

  /**
   The body of both removals, taking the name the edit is offered back under —
   the one thing Remove and Clear Completed disagree about.
   */
  private func removeItems(_ ids: Set<UUID>, named name: QueueEditName) {
    // Registered first: the rows the items occupy and the selection they are
    // part of are exactly what undo has to restore, and the removal below
    // destroys both.
    registerRestore(of: ids, named: name)
    for id in ids {
      runTasks[id]?.cancel()
      runTasks[id] = nil
      pending.removeAll { $0 == id }
      monitors[id] = nil
    }
    items.removeAll { ids.contains($0.id) }
    pendingProbes.removeAll { ids.contains($0.id) }
    selection.subtract(ids)
    refreshOutputNames()
    onPersistableChange()
    onEncodeActivityChanged()
  }

  /**
   Reorders the given items to sit at `destination`, so the queue order (and
   thus the run order used by ``startAll()``) matches the table. Only
   reorderable items move; a set with nothing reorderable, and any drop that
   would leave the order as it is, are ignored. Undoable.

   - Parameter ids: The items to move. Ones that can't be reordered are left
     where they are.
   - Parameter destination: The row to insert before, counted in the order the
     table is showing now — the same coordinate space `ForEach` reorders in,
     and what the table's drop destination hands over. `items.count` appends.
   */
  public func moveItems(_ ids: Set<UUID>, to destination: Int) {
    let movingIDs = Set(items.filter { ids.contains($0.id) && $0.status.isReorderable }.map(\.id))
    guard !movingIDs.isEmpty else { return }

    let moving = items.filter { movingIDs.contains($0.id) }
    var remaining = items.filter { !movingIDs.contains($0.id) }
    // The drop index counts rows the table is showing, so it shifts up by every
    // moving row above it once those are lifted out.
    let above = items.prefix(min(destination, items.count))
    let liftedAbove = above.count { movingIDs.contains($0.id) }
    let insertionIndex = min(max(destination - liftedAbove, 0), remaining.count)
    remaining.insert(contentsOf: moving, at: insertionIndex)
    // Sited past every guard above, and past the no-op check, so a drop that
    // changes nothing registers nothing and Undo never offers back an edit that
    // didn't happen.
    guard remaining.map(\.id) != items.map(\.id) else { return }
    registerOrderRestore()
    items = remaining
    refreshOutputNames()
    onPersistableChange()
  }

  // MARK: - Running

  /**
   Starts every startable item, unless the queue's name format would have a run
   destroy a file (see ``outputNameConflicts``).
   */
  public func startAll() {
    guard outputNameConflicts.isEmpty else { return }
    enqueue(items.filter(\.status.isStartable).map(\.id))
  }

  /**
   Starts the given items, unless the queue's name format would have a run
   destroy a file (see ``outputNameConflicts``).
   */
  public func start(_ ids: Set<UUID>) {
    guard outputNameConflicts.isEmpty else { return }
    enqueue(items.filter { ids.contains($0.id) && $0.status.isStartable }.map(\.id))
  }

  /**
   Cancels the given items: an in-flight run is asked to stop (settling to
   `.cancelled` once it unwinds), and an item still waiting its turn is pulled
   out of the queue and settled to `.cancelled` directly. An item that's
   neither running nor pending — including one being re-probed, which has no
   handle to interrupt — is left alone.
   */
  public func cancel(_ ids: Set<UUID>) {
    for id in ids {
      let wasPending = pending.contains(id)
      pending.removeAll { $0 == id }
      if let task = runTasks[id] {
        task.cancel()
      } else if wasPending, let item = item(id) {
        settle(item, .cancelled)
      }
    }
    onEncodeActivityChanged()
  }

  /// Cancels everything.
  public func cancelAll() { cancel(Set(items.map(\.id))) }

  private func enqueue(_ ids: [UUID]) {
    for id in ids where !pending.contains(id) && runTasks[id] == nil {
      pending.append(id)
    }
    pump()
  }

  /**
   Starts as many pending, startable items as the shared governor's global
   limit allows, claiming a slot per item and leaving the rest pending until a
   slot frees. `enqueue` admits any startable item — including a `.failed` or
   `.cancelled` one restarted from a prior run — so `pump` starts any
   startable item in turn; `runItem` hands each to the engine, which performs
   its own probe, so a missing cached container is not a problem.
   */
  private func pump() {
    while let index = pending.firstIndex(where: { item($0)?.status.isStartable ?? false }) {
      guard governor.acquire() else { break }
      let id = pending.remove(at: index)
      if let item = item(id) {
        runItem(item)
      } else {
        governor.release()
      }
    }
    onEncodeActivityChanged()
  }

  /**
   Applies a settled state to `item`, prunes it from `pending` if it landed
   anywhere but `.ready` (a settled item leaving `.ready` by some route other
   than `pump()` starting it — a re-scan, a source going missing — must not
   leave a stale id parked in the run queue), and notifies the persistence
   hook. Transient states (`probing`/`running`) and `progress` updates bypass
   this so they're never written through.
   */
  private func settle(_ item: QueueItem, _ state: QueueItemState) {
    item.status = state
    if state != .ready { pending.removeAll { $0 == item.id } }
    onPersistableChange()
    onEncodeActivityChanged()
  }

  /**
   Records what a finished run accomplished — the output file's size and how
   many tracks were dropped — then settles `item` to ``QueueItemState/done``.
   Both metrics are nil-safe: a failed stat or an unprobed container simply
   leaves that number `nil`. Called while the run still holds scoped access to
   the output, so the stat succeeds under the sandbox.
   */
  private func complete(_ item: QueueItem) {
    item.progress = 1
    item.writtenByteCount = nil
    item.outputByteCount = try? item.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
    item.tracksRemoved = tracksRemoved(for: item)
    settle(item, .done)
  }

  /**
   Begins security-scoped write access for `item`'s output. Output landing in
   the queue's destination folder is covered by that folder's own bookmark;
   anything else — output written alongside its source, or a per-item override
   — is covered only by the item's own folder bookmark.
   */
  private func beginOutputAccess(_ item: QueueItem) -> ScopedAccess {
    settings.destination.covers(item.outputURL)
      ? settings.destination.beginAccess()
      : beginOutputFolderAccess(item)
  }

  /**
   Throws before `ffmpeg` is spawned when the output folder can't be written.

   A source bookmark scopes the source *file*, which lets `ffmpeg` read every
   input and still be denied when it creates the sibling output — a queue
   restored without a folder bookmark fails exactly that way, and `ffmpeg`
   reports it only as an opaque "Operation not permitted". Checking here turns
   it into ``FileAccessError/outputFolderNotWritable(url:)``, which names the
   two ways out.
   */
  private func checkOutputFolderIsWritable(_ item: QueueItem) throws {
    let folder = item.outputURL.deletingLastPathComponent()
    guard FileManager.default.isWritableFile(atPath: folder.path(percentEncoded: false)) else {
      throw FileAccessError.outputFolderNotWritable(url: folder)
    }
  }

  /**
   Throws before `ffmpeg` is spawned when the output volume plainly hasn't room
   for the file the run would write, so filling a disk reads as itself rather
   than as an opaque ``VideoProcessingError/encodeFailed(exitCode:)``.

   Additive, and deliberately easy to satisfy: every unknown lets the run
   proceed. The projection is `nil` for a transcode and for any plan whose
   dropped tracks declare no bit rate, and the volume reports no capacity at
   all over SMB or NFS — a likely destination for this app. A false refusal
   would be worse than the bad error message this replaces, so `ffmpeg`'s own
   out-of-space failure remains the backstop rather than this.

   Concurrent runs each ask independently, so several admitted together can
   still overrun a volume that had room for any one of them.
   */
  private func checkOutputFolderHasRoom(_ item: QueueItem) throws {
    let folder = item.outputURL.deletingLastPathComponent()
    guard let required = estimatedOutputByteCount(for: item),
      let available = availableCapacity(folder),
      required > available
    else { return }
    throw VideoProcessingError.insufficientSpace(required: required, available: available)
  }

  private func runItem(_ item: QueueItem) {
    resetForRun(item)
    let engine = engine
    // Hold security-scoped access to the source and destination for the whole
    // run so the sandboxed `ffmpeg` child can read and write; both released when
    // the task exits. The source is read from its resolved bookmark when present.
    let sourceAccess = beginSourceAccess(item)
    let outputAccess = beginOutputAccess(item)
    logBookmarkLossIfNeeded(for: item, access: sourceAccess)
    let job = item.makeJob(
      source: sourceAccess.resolvedURL ?? item.sourceURL,
      globalRules: settings.rules.rules
    )

    let task = Task { @MainActor in
      defer { sourceAccess.release(); outputAccess.release() }
      do {
        try checkOutputFolderIsWritable(item)
        try checkOutputFolderHasRoom(item)
        for try await event in engine.run(job) { apply(event, to: item) }
        settleAfterRun(item)
      } catch {
        settleAfterRun(item, failedWith: error)
      }
      // Reported here, where the item's status and its freshly-stat'd output
      // size are both current, and where nothing but a run can reach.
      if let outcome = runOutcome(for: item) { onRunSettled(outcome) }
      runTasks[item.id] = nil
      // Releasing the slot wakes every waiting coordinator (including this one)
      // to start whatever the global limit now allows.
      governor.release()
      // `release` pumps every waiting coordinator synchronously, so any queue
      // that could take the freed slot has already claimed it. That makes this
      // the first point at which the app can truthfully be seen to have
      // stopped encoding — checking any earlier reads this run as still in
      // flight, and any later would race the next item.
      onEncodeActivityChanged()
    }
    runTasks[item.id] = task
  }

  /**
   What `item`'s just-settled run came to, or `nil` when it didn't land in a
   state a run produces — which a re-probe racing the run can leave behind.

   Sizes and the output path are read only for a run that finished: neither
   ``resetForRun(_:)`` nor a failure clears ``QueueItem/outputByteCount``, so an
   item re-run after an earlier success still holds the earlier run's number.
   */
  private func runOutcome(for item: QueueItem) -> QueueRunOutcome? {
    let result: QueueRunOutcome.Result
    switch item.status {
      case .done: result = .finished
      case .failed: result = .failed
      case .cancelled: result = .cancelled
      default: return nil
    }
    let finished = result == .finished
    return QueueRunOutcome(
      result: result,
      bytesSaved: finished ? bytesSaved(for: item) : nil,
      outputURL: finished ? item.outputURL : nil
    )
  }

  /// What slimming `item` saved, or `nil` when either size is unknown.
  private func bytesSaved(for item: QueueItem) -> Int? {
    guard let sourceByteCount = item.sourceByteCount, let outputByteCount = item.outputByteCount
    else { return nil }
    return sourceByteCount - outputByteCount
  }

  /**
   Clears the state a previous run left on `item`, so a restart doesn't show
   the earlier attempt's progress or error.
   */
  private func resetForRun(_ item: QueueItem) {
    item.status = .running
    item.progress = 0
    item.writtenByteCount = nil
    item.lastError = nil
  }

  /**
   Logs an unresolvable source bookmark. A bookmark that fails to resolve
   silently downgrades to the raw URL, which the sandbox may no longer reach —
   recording the loss is what makes that diagnosable.
   */
  private func logBookmarkLossIfNeeded(for item: QueueItem, access: ScopedAccess) {
    guard item.sourceBookmark != nil, access.resolvedURL == nil else { return }
    Self.log.warning("\(FileAccessError.bookmarkFailed(url: item.sourceURL).userMessage)")
  }

  /// Folds one engine event into `item`'s live state.
  private func apply(_ event: JobEvent, to item: QueueItem) {
    switch event {
      case .probed(let container): item.container = container
      case .progress(let progress):
        if let fraction = progress.fraction { item.progress = fraction }
        item.writtenByteCount = progress.totalSize
      case .finished: complete(item)
      case .failed(let message): item.lastError = message; settle(item, .failed(message))
      case .probing, .operations: break
    }
  }

  /**
   Settles `item` once its event stream has ended. A cancelled stream ends
   without throwing, so cancellation is checked explicitly; an item the stream
   already settled is left as it landed.
   */
  private func settleAfterRun(_ item: QueueItem) {
    if Task.isCancelled {
      settle(item, .cancelled)
    } else if item.status == .running {
      complete(item)
    }
  }

  /**
   Settles `item` after its run threw, on the same terms as an ended stream:
   cancellation wins, and an item the stream already settled is left alone.
   */
  private func settleAfterRun(_ item: QueueItem, failedWith error: any Error) {
    if Task.isCancelled {
      settle(item, .cancelled)
    } else if item.status == .running {
      item.lastError = error.userMessage
      settle(item, .failed(error.userMessage))
    }
  }

  // MARK: - Probing & missing sources

  /**
   Re-probes the given items, refreshing each cached container. On success a
   finished item settles back to ``QueueItemState/done`` so its savings
   survive, and everything else lands in ``QueueItemState/ready`` (or
   ``QueueItemState/incompatible(_:)``); a probe that fails settles into
   ``QueueItemState/failed(_:)`` or ``QueueItemState/missing`` as it does
   anywhere else. Items being probed or encoded are skipped.
   */
  public func rescan(_ ids: Set<UUID>) {
    for item in items where ids.contains(item.id) && item.status.isRescannable {
      enqueueProbe(item, refreshing: true)
    }
  }

  /**
   Queues `item` for probing behind whatever is already waiting.

   The item's status is deliberately untouched: `probe` reads it when the
   probe actually starts, which is how a re-scan of a finished item knows to
   land back on `.done`.
   */
  private func enqueueProbe(_ item: QueueItem, refreshing: Bool = false) {
    guard
      !activeProbes.contains(item.id),
      !pendingProbes.contains(where: { $0.id == item.id })
    else { return }
    pendingProbes.append(PendingProbe(id: item.id, refreshing: refreshing))
    pumpProbes()
  }

  /**
   Starts queued probes until ``ProbeCoordinator/defaultLimit`` are in flight.

   That coordinator already caps the `ffprobe` processes themselves; matching
   the bound here caps the security scopes, which are taken before the probe
   reaches it.
   */
  private func pumpProbes() {
    while activeProbes.count < ProbeCoordinator.defaultLimit, !pendingProbes.isEmpty {
      let next = pendingProbes.removeFirst()
      guard let item = item(next.id) else { continue }
      probe(item, refreshing: next.refreshing)
    }
  }

  /**
   Inspects `item`, settling it on what `ffprobe` reports.

   - Parameter refreshing: Whether to discard what the engine already knows
     about the source first. A re-scan the user asked for must read the file
     even when nothing about it has changed; every other caller is happy to be
     answered from an earlier inspection.
   */
  private func probe(_ item: QueueItem, refreshing: Bool = false) {
    // A re-scan of a finished item must land back on `done`; every other caller
    // probes an item that can't be finished, so this is a no-op for them.
    let wasDone = item.status == .done
    item.status = .probing
    let engine = engine
    // Hold security-scoped access for the whole probe so the sandboxed `ffprobe`
    // child can read a source whose only remaining grant is a stored bookmark —
    // every source added before this launch, and every re-scan of one.
    let sourceAccess = beginSourceAccess(item)
    logBookmarkLossIfNeeded(for: item, access: sourceAccess)
    let source = sourceAccess.resolvedURL ?? item.sourceURL

    activeProbes.insert(item.id)
    Task { @MainActor in
      defer {
        sourceAccess.release()
        activeProbes.remove(item.id)
        pumpProbes()
      }
      do {
        if refreshing { await engine.invalidateProbe(source) }
        let container = try await engine.probe(source)
        item.container = container
        if item.status == .probing {
          settle(item, wasDone ? .done : readyOrIncompatible(item))
        }
        pump()
      } catch {
        let path = source.path(percentEncoded: false)
        Self.log.error(
          "Probe of \(path, privacy: .public) failed: \(error.userMessage, privacy: .public)"
        )
        if fileExists(source) {
          item.lastError = error.userMessage
          settle(item, .failed(error.userMessage))
        } else {
          item.lastError = FileAccessError.sourceMissing(url: item.sourceURL).userMessage
          settle(item, .missing)
        }
      }
    }
  }

  private func startMonitoring(_ item: QueueItem) {
    monitors[item.id] = SourceFileMonitor(url: item.sourceURL) { [weak self, weak item] in
      guard let self, let item else { return }
      self.revalidate(item)
    }
  }

  /**
   Re-checks a source file's existence, transitioning to/from `.missing`. A
   recovered file lands in `.incompatible` rather than `.ready` when the
   selected build still can't perform its transcode.
   */
  public func revalidate(_ item: QueueItem) {
    let exists = fileExists(item.sourceURL)
    if !exists {
      if item.status != .running { settle(item, .missing) }
    } else if item.status == .missing {
      if item.container == nil {
        item.status = .waiting
        enqueueProbe(item)
      } else {
        settle(item, readyOrIncompatible(item))
      }
    }
  }

  private func item(_ id: UUID) -> QueueItem? { items.first { $0.id == id } }

  private func fileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  // MARK: - Nested types

  /// An item queued for probing, and whether its probe must re-read the file.
  private struct PendingProbe {
    let id: UUID
    let refreshing: Bool
  }
}

// MARK: - Derived state

extension QueueCoordinator {

  /**
   Maximum number of encodes to run at once, shared globally across every
   queue. A passthrough to the ``EncodeGovernor`` so the Settings stepper's
   `$queue.maxConcurrent` binding sets the one global limit.
   */
  public var maxConcurrent: Int {
    get { governor.limit }
    set { governor.limit = newValue }
  }

  /// Whether any item is probing or encoding.
  public var isRunning: Bool { !runTasks.isEmpty || items.contains { $0.status == .probing } }

  /**
   Whether this queue has encoding in flight or waiting on the global limit —
   the queue's share of the answer to "is the app still working?", which
   ``Workspace`` sums across every queue to know when a run has ended.

   Unlike ``isRunning`` this ignores probing on its own, so the probes a launch
   or an inspector re-scan kicks off never read as a run. A *pending* item being
   re-probed still counts, because it will come back `.ready` and run.

   The pending side mirrors `pump()`'s own predicate rather than just testing
   for an empty queue: `pump` never removes an id whose item isn't startable,
   and `settle(_:_:)` prunes one only when it lands somewhere other than
   `.ready`, so a bare `!pending.isEmpty` would leave a stranded id claiming the
   app is forever busy.
   */
  public var hasEncodeWorkInFlight: Bool {
    if !runTasks.isEmpty { return true }
    return pending.contains { id in
      guard let item = item(id) else { return false }
      return item.status.isStartable || item.status == .probing
    }
  }

  /// Number of items currently encoding.
  public var activeCount: Int { items.count { $0.status == .running } }

  /**
   Overall progress across the whole queue (`0...1`): a finished item counts in
   full, an encode in flight counts for how far it has got, and anything still
   queued counts for nothing — so the fraction tracks the work left to do
   rather than how the started items are faring.
   */
  public var overallProgress: Double {
    guard !items.isEmpty else { return 0 }
    return items.reduce(0.0) { $0 + $1.progressWeight } / Double(items.count)
  }

  /// The number of completed (slimmed) items.
  public var slimmedCount: Int { items.count { $0.status == .done } }

  /**
   Whether the queue holds work that a delete would interrupt: an in-flight
   run, or any item still queued to run. Drives the sidebar's delete
   confirmation. A queue of only finished, cancelled, or missing items has
   nothing to interrupt.
   */
  public var hasUnfinishedWork: Bool {
    isRunning || items.contains { $0.status.isActive || $0.status.isStartable }
  }

  /**
   The queue's rolled-up state for the sidebar icon: encoding takes
   precedence, then anything needing attention (missing/failed/incompatible),
   then an all-done queue, otherwise idle.
   */
  public var aggregateStatus: QueueAggregateStatus {
    if isRunning { return .running(overallProgress) }
    if items.contains(where: \.status.needsAttention) { return .attention }
    if !items.isEmpty, items.allSatisfy({ $0.status == .done }) { return .done }
    return .idle
  }

  /**
   A `Sendable` snapshot of this queue and its items in run order, for the
   persistence layer to write through. Item `sortIndex` is renumbered to the
   current order; the reason carried by `failed`/`incompatible` rides in
   `lastError`.
   */
  public var snapshot: QueueSnapshot {
    QueueSnapshot(
      id: id,
      name: name,
      sortIndex: sortIndex,
      rules: settings.rules.rules,
      naming: settings.naming,
      activePresetID: settings.rules.activePresetID,
      destinationBookmark: settings.destination.bookmarkData,
      items: items.enumerated().map { offset, item in
        QueueItemSnapshot(
          id: item.id,
          sortIndex: offset,
          sourcePath: item.sourceURL.path(percentEncoded: false),
          sourceBookmark: item.sourceBookmark,
          outputPath: item.outputURL.path(percentEncoded: false),
          customName: item.customName,
          outputFolderBookmark: item.outputFolderBookmark,
          status: PersistedItemStatus(item.status),
          lastError: item.status.persistedReason,
          selection: item.selection,
          sourceByteCount: item.sourceByteCount,
          outputByteCount: item.outputByteCount,
          tracksRemoved: item.tracksRemoved
        )
      }
    )
  }
}

// MARK: - Output names

extension QueueCoordinator {

  /**
   Every way the queue's current name format would have a run destroy a file:
   two items writing to one path, or an item writing over its own source.
   Non-empty blocks the queue from starting.
   */
  public var outputNameConflicts: [OutputNameConflict] {
    OutputNameConflict.conflicts(in: items.map { (source: $0.sourceURL, output: $0.outputURL) })
  }

  /**
   Names `item`'s output explicitly, or hands it back to the queue's name
   format when `name` is `nil`. Restates the output paths and writes the edit
   through — the per-item counterpart to ``settingsDidChange()``.
   */
  public func setCustomName(_ name: String?, for item: QueueItem) {
    guard name != item.customName else { return }
    item.customName = name
    refreshOutputNames()
    onPersistableChange()
  }

  /**
   The file name the queue's format gives `item` at its current position —
   what the item is called when it has no ``QueueItem/customName``, and the
   starting point the name field offers when the user takes it over.
   */
  public func defaultOutputName(for item: QueueItem) -> String {
    guard let position = items.firstIndex(where: { $0.id == item.id }) else {
      return item.outputURL.lastPathComponent
    }
    return settings.naming.fileName(for: item.sourceURL, position: position + 1)
  }

  /**
   Where `item` at `position` is written: under its own name when the user
   gave it one, otherwise under the queue's current name format — either way
   inside the destination folder when the queue has one, and beside the source
   when it hasn't.
   */
  private func outputURL(for item: QueueItem, position: Int) -> URL {
    outputURL(for: item.sourceURL, position: position, customName: item.customName)
  }

  private func outputURL(for source: URL, position: Int, customName: String?) -> URL {
    let destination = settings.destination.destinationURL
    guard let customName else {
      return settings.naming.outputURL(for: source, position: position, in: destination)
    }
    return OutputNameFormat.outputURL(customBase: customName, for: source, in: destination)
  }

  /**
   Restates every pending item's output path from the queue's current name
   format and destination. A finished item keeps the path it was written to and
   a running one keeps writing where it started, so neither is disturbed.

   Every item is numbered, including the ones the user has named explicitly, so
   giving one file its own name never renumbers the `{n}` of the files around
   it.

   An item's own folder grant is re-derived only when the output moves to a
   different folder — renaming in place must not discard the working bookmark
   captured when the item was added, which can't be minted again once the
   transient grant that produced it is gone.
   */
  private func refreshOutputNames() {
    for (index, item) in items.enumerated() where !item.status.keepsOutputPath {
      let output = outputURL(for: item, position: index + 1)
      let previousFolder = item.outputURL.deletingLastPathComponent()
      item.outputURL = output
      let folder = output.deletingLastPathComponent()
      guard folder != previousFolder else { continue }
      item.outputFolderBookmark = settings.destination.covers(output) ? nil : makeBookmark(folder)
    }
  }
}

// MARK: - FFmpeg compatibility

extension QueueCoordinator {

  /**
   Re-probes the currently-resolved `ffmpeg`, refreshes cached capabilities,
   then revalidates every item — the analogue of a `SourceFileMonitor` event
   for the "selected binary can't encode this" axis. Call after the
   FFmpeg-location setting changes (and once at launch).
   */
  public func ffmpegLocationChanged() {
    Task { @MainActor in
      if let capabilities = await probeCapabilities() { encoderCapabilities = capabilities }
      #if DEBUG
        if let override = encoderCapabilitiesOverride { encoderCapabilities = override }
      #endif
      revalidateAllCompatibility()
    }
  }

  /// Revalidates compatibility for every item.
  public func revalidateAllCompatibility() {
    for item in items { revalidateCompatibility(item) }
  }

  /**
   Moves an item between `.ready` and `.incompatible` to match the selected
   build's capabilities. Acts only on items on this axis (`.ready` /
   `.incompatible`); other states are governed by their own transitions.
   */
  public func revalidateCompatibility(_ item: QueueItem) {
    switch item.status {
      case .ready, .incompatible: settle(item, readyOrIncompatible(item))
      default: break
    }
  }

  /**
   The reason the selected build can't perform `item`'s transcode, or `nil`
   when it can. Runs the item's kept-stream operations through the shared
   ``EncoderCapabilities/firstUnsupported(in:)`` checkpoint.
   */
  public func incompatibilityReason(_ item: QueueItem) -> String? {
    guard item.container != nil else { return nil }
    guard let (_, codec) = encoderCapabilities.firstUnsupported(in: plannedOperations(for: item))
    else {
      return nil
    }
    return String(
      localized: "The “\(codec)” encoder isn’t available in the current FFmpeg",
      bundle: #bundle
    )
  }

  /**
   How many managed (video/audio/subtitle) tracks slimming `item` would drop —
   its probed track count minus the count of kept operations, clamped at 0.
   `nil` before the container is probed.
   */
  public func tracksRemoved(for item: QueueItem) -> Int? {
    guard let managed = item.managedTrackCount else { return nil }
    return max(0, managed - plannedOperations(for: item).count)
  }

  /**
   How many managed tracks `item`'s output holds: what the finished run left
   behind once it has run, and until then how many the current plan keeps —
   so editing the rules restates every pending item's answer. `nil` before the
   container is probed.
   */
  public func outputTrackCount(for item: QueueItem) -> Int? {
    guard item.container != nil else { return nil }
    if item.status == .done, let finishedTrackCount = item.finishedTrackCount {
      return finishedTrackCount
    }
    return plannedOperations(for: item).count
  }

  /**
   A warning for an item whose plan would drop every audio track its source
   has, naming the languages being lost; `nil` when audio survives, when the
   source has none to begin with, or before the container is probed.

   Derived from the plan rather than from a finished run, so it appears and
   clears as the queue's rules are edited.
   */
  public func audioLossWarning(for item: QueueItem) -> String? {
    guard let container = item.container else { return nil }
    let audioStreams = container.audioStreams
    guard !audioStreams.isEmpty else { return nil }
    guard !plannedOperations(for: item).contains(where: { $0.streamType == .audio }) else {
      return nil
    }
    let languages = droppedAudioLanguages(audioStreams)
    return String(
      localized: """
        Output would have no audio. The source’s audio (\(languages)) isn’t kept by the current \
        rules.
        """,
      bundle: #bundle
    )
  }

  /**
   The distinct languages of `streams`, in source order, as a localized list —
   display names where the tag is recognized, the raw tag where it isn't, and
   “untagged” for a track carrying no language at all.
   */
  private func droppedAudioLanguages(_ streams: [AudioStream]) -> String {
    var seen = Set<String>()
    let names = streams.compactMap { stream -> String? in
      let name =
        stream.language.flatMap(LanguageCatalog.name(for:))
        ?? stream.language
        ?? String(localized: "untagged", bundle: #bundle)
      return seen.insert(name).inserted ? name : nil
    }
    return names.formatted(.list(type: .and))
  }

  /**
   The output size to show for `item`: measured off the finished file, else
   the size an in-flight run is on course for, else what the planned track
   drops would leave. `nil` when none of the three can be had.
   */
  public func outputSize(for item: QueueItem) -> OutputSize? {
    if item.status == .done, let outputByteCount = item.outputByteCount {
      return .measured(outputByteCount)
    }
    let estimate = item.projectedOutputByteCount ?? estimatedOutputByteCount(for: item)
    return estimate.map(OutputSize.estimated)
  }

  /**
   What slimming `item` would leave behind: its source size less the bytes of
   the tracks the plan drops.

   `nil` when the source size or container is unknown, when a dropped track
   declares no bit rate, or when the plan re-encodes anything — a transcode's
   size doesn't follow from the source's.
   */
  private func estimatedOutputByteCount(for item: QueueItem) -> Int? {
    guard let sourceByteCount = item.sourceByteCount, let container = item.container else {
      return nil
    }
    let operations = plannedOperations(for: item)
    guard !operations.isEmpty, operations.allSatisfy({ $0.kind == .copy }) else { return nil }
    let keptIndices = Set(operations.map(\.streamIndex))
    guard let droppedByteCount = container.byteCount(ofStreamsExcluding: keptIndices) else {
      return nil
    }
    return max(0, sourceByteCount - droppedByteCount)
  }

  /**
   The kept-stream operations the run performs for `item`: its per-file
   selection when set, otherwise the operations the queue's rules derive from
   the probed container. Empty when the container isn't known or the rules
   can't produce a converter.
   */
  private func plannedOperations(for item: QueueItem) -> [StreamOperation] {
    if let selection = item.selection { return selection.operations() }
    guard let container = item.container else { return [] }
    return (try? settings.rules.rules.makeConverter(container: container).operations()) ?? []
  }

  /**
   `.incompatible(reason)` when the selected build can't run `item`'s
   transcode, else `.ready`.
   */
  private func readyOrIncompatible(_ item: QueueItem) -> QueueItemState {
    incompatibilityReason(item).map(QueueItemState.incompatible) ?? .ready
  }
}

// MARK: - Undo

/**
 What an undoable queue edit is called, registered as the undo action's name.

 SwiftUI's stock Edit menu labels its items a flat “Undo”/“Redo” rather than
 reading the name back, so this is not on screen today. It is registered
 regardless: it is what ``UndoManager/undoActionName`` answers, and it is what
 keeps a redone Clear Completed from describing itself as a plain removal.
 */
private enum QueueEditName {
  case removeFromQueue
  case clearCompleted
  case reorderQueue

  var localized: String {
    switch self {
      case .removeFromQueue: String(localized: "Remove from Queue", bundle: #bundle)
      case .clearCompleted: String(localized: "Clear Completed", bundle: #bundle)
      case .reorderQueue: String(localized: "Reorder Queue", bundle: #bundle)
    }
  }
}

extension QueueCoordinator {

  /**
   Registers the undo that puts `ids` back where they sit now. Registering
   nothing when nothing matches is what keeps a Clear Completed with nothing
   finished from consuming the user's ⌘Z.

   The items themselves are captured, not a description of them: ``QueueItem``
   has no id-taking initializer, and its security-scoped bookmarks were minted
   from a transient grant that is long gone, so a rebuilt item could never read
   its source or write beside it again.
   */
  private func registerRestore(of ids: Set<UUID>, named name: QueueEditName) {
    let removals = items.enumerated()
      .filter { ids.contains($1.id) }
      .map { RemovedItem(item: $1, index: $0) }
    guard !removals.isEmpty else { return }
    let priorSelection = selection
    registerUndo(named: name) { coordinator in
      coordinator.restore(removals, selection: priorSelection, named: name)
    }
  }

  /// Registers the removal that redoes a restore, under the same action name.
  private func registerRemoval(of ids: Set<UUID>, named name: QueueEditName) {
    registerUndo(named: name) { coordinator in
      coordinator.removeItems(ids, named: name)
    }
  }

  /**
   Registers the undo that puts the queue back in the order it is in now.

   ``moveItems(_:before:)`` is not its own inverse — one drop can gather rows
   from three places and land them together, and no second drop separates them
   again — so undo restores the whole order rather than moving anything back.
   */
  private func registerOrderRestore() {
    let order = items.map(\.id)
    registerUndo(named: .reorderQueue) { coordinator in
      coordinator.restoreOrder(order)
    }
  }

  /**
   Registers `body` as the way back from the edit about to be made.

   Every registration goes through here, so ``onUndoAppliedChange`` fires for a
   redo as much as an undo: a redo is registered by this same path while the
   manager is undoing, which is also the whole of how redo works here. Guarding
   a registration on ``UndoManager/isUndoing`` would make redo a dead end.
   */
  private func registerUndo(
    named name: QueueEditName,
    _ body: @escaping @MainActor (QueueCoordinator) -> Void
  ) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { coordinator in
      body(coordinator)
      coordinator.onUndoAppliedChange()
    }
    undoManager.setActionName(name.localized)
  }

  /**
   Puts removed items back in the rows they came out of, re-arms their source
   monitors, restores the selection they were part of, and registers the
   removal that redoes the edit.
   */
  private func restore(
    _ removals: [RemovedItem],
    selection restoredSelection: Set<UUID>,
    named name: QueueEditName
  ) {
    registerRemoval(of: Set(removals.map(\.item.id)), named: name)
    for removal in removals.sorted(by: { $0.index < $1.index }) {
      guard !items.contains(where: { $0.id == removal.item.id }) else { continue }
      // Clamped, because the queue can have shrunk since — items added and
      // removed again while this removal sat on the undo stack.
      items.insert(removal.item, at: min(removal.index, items.count))
      settleForRestore(removal.item)
      startMonitoring(removal.item)
    }
    selection = restoredSelection.filter { id in items.contains { $0.id == id } }
    refreshOutputNames()
    onPersistableChange()
    onEncodeActivityChanged()
  }

  /**
   Brings a restored item back to a state something is still driving.

   A run the removal cancelled reads as cancelled. The run's own unwind settles
   it the same way — the task holds the item rather than looking it up — but a
   restored row must never be seen running with nothing behind it. Nothing
   partial comes back with it: a run stages its output elsewhere and commits it
   atomically, so a cancelled run left no file at ``QueueItem/outputURL``, and
   ``QueueItem/outputByteCount`` is only ever written by a run that finished.

   An item still waiting on a probe is queued for a fresh one, because the
   removal dropped the one it had, and nothing else would ever move it on. One
   whose probe is already *in flight* is left alone: that probe holds the item
   directly and settles it whatever the queue does.

   Settling here rather than after ``refreshOutputNames()`` is deliberate:
   ``QueueItemState/running`` keeps its output path, so a row still marked as
   running would miss the renumbering that put it back.
   */
  private func settleForRestore(_ item: QueueItem) {
    switch item.status {
      case .running:
        item.status = .cancelled
      case .waiting:
        enqueueProbe(item)
      case .probing where !activeProbes.contains(item.id):
        item.status = .waiting
        enqueueProbe(item)
      default:
        break
    }
  }

  /**
   Rearranges the queue into the `order` an undone or redone drag recorded, and
   registers the order it found as the way back.

   Rows added since are left at the end in the order they arrived and ids no
   longer queued are skipped, so a restore can never lose one. The tiebreak on
   position is load-bearing: `sorted(by:)` is not stable, and every added row
   shares one fallback rank.
   */
  private func restoreOrder(_ order: [UUID]) {
    registerOrderRestore()
    let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    items = items.enumerated()
      .sorted {
        (rank[$0.element.id] ?? order.count + $0.offset)
          < (rank[$1.element.id] ?? order.count + $1.offset)
      }
      .map(\.element)
    refreshOutputNames()
    onPersistableChange()
  }

  /// An item a removal lifted out of the queue, and the row it sat in.
  private struct RemovedItem {
    let item: QueueItem
    let index: Int
  }
}
