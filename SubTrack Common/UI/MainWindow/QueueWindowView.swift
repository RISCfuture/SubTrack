import SwiftUI

/**
 The main window: a destination bar, the queue (or an empty state), a status
 bar, a trailing inspector, and the toolbar.
 */
struct QueueWindowView: View {
  @Environment(AppEnvironment.self)
  private var env
  /**
   The window's undo manager, which the queues register their destructive edits
   with. Read here rather than in ``SubTrackCommands`` because the environment
   value is nil inside `Commands` — a menu lives outside any window — and the
   Queue menu is where two of the three undoable edits are invoked.
   */
  @Environment(\.undoManager)
  private var undoManager
  @State private var dropTargeted = false

  var body: some View {
    @Bindable var ui = env.ui
    VStack(spacing: 0) {
      DestinationBar()
      Divider()
      QueueContentView()
      Divider()
      QueueStatusBar()
    }
    .toolbar { QueueToolbar() }
    .inspector(isPresented: $ui.inspectorVisible) {
      InspectorView()
        // Wide enough for the Preview tab's five columns to stand side by side.
        // The Rules and Override tabs were comfortable at 300, but a table of
        // tracks is the widest thing the pane holds, and `Table` lays its
        // columns out at their ideal widths and lets the last one overhang
        // rather than compressing them — so the table's needs set the floor.
        .inspectorColumnWidth(min: 320, ideal: 360, max: 480)
    }
    .dropDestination(for: URL.self) { urls, _ in
      env.queue.ingest(urls)
      return true
    } isTargeted: {
      dropTargeted = $0
    }
    .overlay {
      if dropTargeted { DropOverlay() }
    }
    .onOpenURL { env.queue.ingest([$0]) }
    .onChange(of: undoManager, initial: true) { _, undoManager in
      env.workspace.undoManager = undoManager
    }
    .sheet(isPresented: ingestSheetPresented) {
      if let progress = env.queue.ingestProgress {
        IngestProgressSheet(progress: progress) { progress.cancel() }
      }
    }
  }

  /**
   Presented for as long as an ingest is running. Dismissing — by Escape or
   the sheet's own button — asks that ingest to stop rather than merely
   hiding the sheet, so the two can't disagree about whether work is running.
   */
  private var ingestSheetPresented: Binding<Bool> {
    Binding(
      get: { env.queue.ingestProgress != nil },
      set: { if !$0 { env.queue.ingestProgress?.cancel() } }
    )
  }

  /// Creates the queue window view.
  init() {}
}

/// Shows the empty state or the queue table depending on whether files are queued.
private struct QueueContentView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    if env.queue.items.isEmpty {
      EmptyStateView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      QueueTableView()
    }
  }
}

/// A translucent overlay shown while a drag is over the window.
private struct DropOverlay: View {
  private static let cornerRadius: Double = 16
  private static let borderWidth: Double = 3
  private static let dashLength: Double = 10
  private static let fillOpacity: Double = 0.08
  private static let inset: Double = 12

  var body: some View {
    outline
      .strokeBorder(
        .tint,
        style: StrokeStyle(lineWidth: Self.borderWidth, dash: [Self.dashLength])
      )
      .background(.tint.opacity(Self.fillOpacity), in: outline)
      .padding(Self.inset)
      .allowsHitTesting(false)
  }

  private var outline: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius)
  }
}

#if DEBUG
  #Preview("Window — populated") {
    QueueWindowView()
      .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
      .frame(minWidth: 900, minHeight: 600)
  }

  #Preview("Window — empty") {
    QueueWindowView()
      .environment(PreviewSupport.environment())
      .frame(minWidth: 900, minHeight: 600)
  }

  #Preview("Content — empty vs populated") {
    VStack(spacing: 0) {
      QueueContentView()
        .environment(PreviewSupport.environment())
        .frame(minWidth: 700, minHeight: 200)
      Divider()
      QueueContentView()
        .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
        .frame(minWidth: 700, minHeight: 200)
    }
  }
#endif
