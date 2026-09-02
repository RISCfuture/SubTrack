import SwiftUI

/**
 The queue as a multi-select `Table` whose rows drag to reorder and whose
 columns the user can hide.

 Deliberately not paired with a `sortOrder:` binding. Queue order *is* execution
 order, and the `rows:` builder below reorders by drag; a sort would show rows in
 an order that doesn't match what runs next.
 */
struct QueueTableView: View {
  @Environment(AppEnvironment.self)
  private var env

  /**
   Which columns are shown, and in what order. Five of the seven are narrow
   capped metrics crowding Name, so hiding the ones a given user doesn't read
   hands that width back.
   */
  @AppStorage(QueueTableDefaults.columnCustomizationKey)
  private var columnCustomization: TableColumnCustomization<QueueItem>

  var body: some View {
    @Bindable var queue = env.queue
    Table(
      of: QueueItem.self,
      selection: $queue.selection,
      columnCustomization: $columnCustomization
    ) {
      TableColumn("") { StatusCell(item: $0) }
        .width(28)
      TableColumn(LocalizedStringResource("Name", bundle: #bundle)) {
        NameCell(item: $0, audioWarning: env.queue.audioLossWarning(for: $0))
      }
      .width(min: 180, ideal: 300)
      .customizationID("name")
      .disabledCustomizationBehavior(.visibility)
      TableColumn(LocalizedStringResource("Input Tracks", bundle: #bundle)) {
        MetricCell(text: $0.managedTrackCount?.formatted(.number))
      }
      .width(min: 55, ideal: 70, max: 70)
      .customizationID("inputTracks")
      TableColumn(LocalizedStringResource("Output Tracks", bundle: #bundle)) {
        OutputTracksCell(item: $0)
      }
      .width(min: 55, ideal: 80, max: 80)
      .customizationID("outputTracks")
      TableColumn(LocalizedStringResource("Input Size", bundle: #bundle)) {
        MetricCell(text: $0.sourceByteCount?.formatted(.byteCount(style: .file)))
      }
      .width(min: 65, ideal: 85, max: 85)
      .customizationID("inputSize")
      TableColumn(LocalizedStringResource("Output Size", bundle: #bundle)) {
        OutputSizeCell(item: $0)
      }
      .width(min: 65, ideal: 95, max: 95)
      .customizationID("outputSize")
      TableColumn(LocalizedStringResource("Destination", bundle: #bundle)) { item in
        Text(item.outputURL.lastPathComponent)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("queue.cell.destination")
      }
      .width(min: 100, ideal: 160)
      .customizationID("destination")
    } rows: {
      ForEach(env.queue.items) { item in
        let row = TableRow(item)
        if item.status.isReorderable {
          row.draggable(QueueItemDragPayload(id: item.id))
        } else {
          row
        }
      }
      .dropDestination(for: QueueItemDragPayload.self) { index, payloads in
        env.queue.moveItems(Set(payloads.map(\.id)), to: index)
      }
    }
    .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
      QueueRowMenu(ids: ids)
    }
    .accessibilityIdentifier("queue.table")
  }
}

/**
 Where the queue table's column layout is persisted. The leading status column
 has no identifier of its own, so it is never customizable and never reaches the
 header menu as a blank entry; the rest are stable and non-localized, because a
 saved layout has to survive both app updates and a language change.
 */
enum QueueTableDefaults {
  static let columnCustomizationKey = "queueTableColumnCustomization"
}

/**
 Right-click actions for the queue's current selection. `Table` routes a
 right-click inside the selection to all of it and one outside it to that row
 alone, so every action here is set-based.
 */
private struct QueueRowMenu: View {
  @Environment(AppEnvironment.self)
  private var env
  let ids: Set<QueueItem.ID>

  var body: some View {
    if !ids.isEmpty {
      Button(LocalizedStringResource("Start", bundle: #bundle)) { env.queue.start(ids) }
        .disabled(!selectedItems.contains(where: \.status.isStartable))
      Button(LocalizedStringResource("Cancel", bundle: #bundle)) { env.queue.cancel(ids) }
        .disabled(!selectedItems.contains(where: \.status.isActive))
      Button(LocalizedStringResource("Re-scan", bundle: #bundle)) { env.queue.rescan(ids) }
        .disabled(!selectedItems.contains(where: \.status.isRescannable))
      Divider()
      Button(LocalizedStringResource("Reveal Output in Finder", bundle: #bundle)) {
        reveal(writtenOutputURLs)
      }
      .disabled(writtenOutputURLs.isEmpty)
      Button(LocalizedStringResource("Reveal Source in Finder", bundle: #bundle)) {
        reveal(selectedItems.map(\.sourceURL))
      }
      Divider()
      Button(LocalizedStringResource("Remove", bundle: #bundle), role: .destructive) {
        env.queue.remove(ids)
      }
    }
  }

  /// The selected items, in queue order.
  private var selectedItems: [QueueItem] {
    env.queue.items.filter { ids.contains($0.id) }
  }

  /// The selected outputs a run has put on disk — the only ones Finder can select.
  private var writtenOutputURLs: [URL] {
    selectedItems.filter(\.status.holdsWrittenOutput).map(\.outputURL)
  }

  private func reveal(_ urls: [URL]) {
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}

#if DEBUG
  // Wide enough for every column to show at its ideal width. A narrower frame
  // drops the trailing columns, which is what the real window does too once the
  // inspector claims its share — but it makes the intended layout impossible to
  // see here.
  #Preview("Queue Table") {
    QueueTableView()
      .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
      .frame(minWidth: 1100, minHeight: 380)
  }

  #Preview("Queue Table — empty") {
    QueueTableView()
      .environment(PreviewSupport.environment())
      .frame(minWidth: 760, minHeight: 200)
  }
#endif
