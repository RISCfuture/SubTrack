import SwiftUI

/**
 The aggregate status glyph: a determinate progress ring while encoding, a
 warning triangle for attention, a check for a finished queue, nothing when
 idle. Mirrors the per-item treatment in the queue table: the ring and check
 read monochrome in `.secondary` like ``StatusCell``, and the attention
 triangle carries the same orange the table's name column uses.
 */
struct QueueStatusIcon: View {
  let status: QueueAggregateStatus

  var body: some View {
    switch status {
      case .running(let fraction):
        ProgressView(value: fraction)
          .progressViewStyle(.circular)
          .controlSize(.small)
          .tint(.secondary)
          .accessibilityLabel("Encoding")
      case .attention:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel("Needs attention")
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.secondary)
          .accessibilityLabel("All done")
      case .idle:
        EmptyView()
    }
  }
}

#if DEBUG
  #Preview("Status Icons") {
    let states: [(String, QueueAggregateStatus)] = [
      ("Encoding", .running(0.6)),
      ("Attention", .attention),
      ("Done", .done),
      ("Idle", .idle)
    ]
    return List {
      ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
        LabeledContent(entry.0) { QueueStatusIcon(status: entry.1) }
      }
    }
    .frame(width: 220, height: 200)
  }
#endif
