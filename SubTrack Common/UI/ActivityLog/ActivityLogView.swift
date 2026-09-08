import SwiftUI

/**
 A simple activity view listing each item's status and any error, for
 troubleshooting.

 A `Table`, so the three fields keep their headers and their resizable columns,
 with every cell wrapping to as many lines as its text needs rather than
 truncating. A failure message carries its recovery suggestion at the end — the
 fix to try, or where a finished file was left — so the tail of the string is
 the half worth reading, and abbreviating a cell would take exactly that.
 */
struct ActivityLogView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    Table(env.queue.items) {
      TableColumn(LocalizedStringResource("File", bundle: #bundle)) { item in
        WrappingCell(text: item.displayName)
      }
      TableColumn(LocalizedStringResource("Status", bundle: #bundle)) { item in
        WrappingCell(text: statusText(item))
          .foregroundStyle(color(item))
      }
      TableColumn(LocalizedStringResource("Output", bundle: #bundle)) { item in
        WrappingCell(text: item.outputURL.path(percentEncoded: false))
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("activity.table")
  }

  private func statusText(_ item: QueueItem) -> String {
    switch item.status {
      case .waiting: String(localized: "Waiting", bundle: #bundle)
      case .probing: String(localized: "Inspecting", bundle: #bundle)
      case .ready: String(localized: "Ready", bundle: #bundle)
      case .running:
        String(
          localized: "Encoding \(item.progress, format: .percent.precision(.fractionLength(0)))",
          bundle: #bundle
        )
      case .done: String(localized: "Done", bundle: #bundle)
      case .cancelled: String(localized: "Cancelled", bundle: #bundle)
      case .missing: String(localized: "Source is missing", bundle: #bundle)
      case .incompatible(let reason): reason
      case .failed(let message): String(localized: "Failed: \(message)", bundle: #bundle)
    }
  }

  /**
   The one severity vocabulary the queue table also reads from, so an item
   cannot change tier depending on which window it is shown in.
   */
  private func color(_ item: QueueItem) -> Color {
    (item.status.severity ?? .note).tint
  }
}

/**
 One cell, wrapping to its content and selectable so a message can be pasted
 into a bug report rather than retyped. Growing vertically is the whole reason
 this window is worth opening, so the text is fixed against the vertical
 squeeze a table row would otherwise apply to it.
 */
private struct WrappingCell: View {
  let text: String

  var body: some View {
    Text(text)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if DEBUG
  #Preview("All statuses") {
    ActivityLogView()
      .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
      .frame(minWidth: 620, minHeight: 340)
  }

  #Preview("Empty") {
    ActivityLogView()
      .environment(PreviewSupport.environment())
      .frame(minWidth: 620, minHeight: 240)
  }
#endif
