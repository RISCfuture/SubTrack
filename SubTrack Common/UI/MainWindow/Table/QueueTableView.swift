import SwiftUI

/// The queue as a sortable, multi-select `Table`.
struct QueueTableView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    @Bindable var queue = env.queue
    Table(of: QueueItem.self, selection: $queue.selection) {
      TableColumn("") { StatusCell(item: $0) }
        .width(28)
      TableColumn(LocalizedStringResource("Name", bundle: #bundle)) {
        NameCell(item: $0, audioWarning: env.queue.audioLossWarning(for: $0))
      }
      .width(min: 180, ideal: 300)
      TableColumn(LocalizedStringResource("Input Tracks", bundle: #bundle)) {
        MetricCell(text: $0.managedTrackCount?.formatted(.number))
      }
      .width(min: 55, ideal: 70, max: 70)
      TableColumn(LocalizedStringResource("Output Tracks", bundle: #bundle)) {
        OutputTracksCell(item: $0)
      }
      .width(min: 55, ideal: 80, max: 80)
      TableColumn(LocalizedStringResource("Input Size", bundle: #bundle)) {
        MetricCell(text: $0.sourceByteCount?.formatted(.byteCount(style: .file)))
      }
      .width(min: 65, ideal: 85, max: 85)
      TableColumn(LocalizedStringResource("Output Size", bundle: #bundle)) {
        OutputSizeCell(item: $0)
      }
      .width(min: 65, ideal: 95, max: 95)
      TableColumn(LocalizedStringResource("Destination", bundle: #bundle)) { item in
        Text(item.outputURL.lastPathComponent)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("queue.cell.destination")
      }
      .width(min: 100, ideal: 160)
    } rows: {
      ForEach(env.queue.items) { item in
        let row =
          TableRow(item)
          .dropDestination(for: QueueItemDragPayload.self) { payloads in
            env.queue.moveItems(Set(payloads.map(\.id)), before: item.id)
          }
        if item.status.isReorderable {
          row.draggable(QueueItemDragPayload(id: item.id))
        } else {
          row
        }
      }
    }
    .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
      QueueRowMenu(ids: ids)
    }
    .accessibilityIdentifier("queue.table")
  }
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
