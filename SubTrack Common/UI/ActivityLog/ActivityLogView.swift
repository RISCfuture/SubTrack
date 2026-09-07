import SwiftUI

/**
 A simple activity view listing each item's status and any error, for
 troubleshooting.

 A `List` of stacked rows rather than a `Table` of columns, because the whole
 value of this window is the error text and a `Table` cannot show it. Its rows
 are a fixed height on macOS and clip whatever overflows — dropping
 `lineLimit` does not change that — so a failure whose message names the fix,
 or where a finished file was left, lost exactly the part worth reading. Rows
 here grow to their content and nothing is abbreviated.
 */
struct ActivityLogView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    List(env.queue.items) { item in
      ActivityLogRow(item: item, status: statusText(item), tint: color(item))
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
 One item's line in the log: what it is, how it went, and where its output
 belongs. Every field wraps, since a truncated error is the thing this window
 exists to avoid, and the text is selectable so a message can be pasted into a
 bug report rather than retyped.
 */
private struct ActivityLogRow: View {
  /// Keeps the three lines reading as one entry rather than three.
  private static let lineSpacing: Double = 2

  let item: QueueItem
  let status: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: Self.lineSpacing) {
      Text(item.displayName)
      Text(status)
        .foregroundStyle(tint)
      Text(item.outputURL.path(percentEncoded: false))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
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
