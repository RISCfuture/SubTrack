import SwiftUI

/**
 The aggregate status glyph: a determinate progress ring while encoding, a
 warning triangle for attention, a check for a finished queue, nothing when
 idle. The ring and check read monochrome in `.secondary` like ``StatusCell``;
 the attention triangle is the one coloured glyph, matching the orange the name
 column tints an incompatible row rather than the status column's own grey.
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
          .accessibilityLabel(Text("Encoding", bundle: #bundle))
      case .attention:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel(Text("Needs attention", bundle: #bundle))
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.secondary)
          .accessibilityLabel(Text("All done", bundle: #bundle))
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
