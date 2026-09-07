import SwiftUI

/**
 The aggregate status glyph: a determinate progress ring while encoding, a
 warning triangle for attention, a check for a finished queue, nothing when
 idle. The ring and check read monochrome in `.secondary` like ``StatusCell``;
 the attention triangle is the one coloured glyph, and it carries the tier of
 the loudest item beneath it — red where a queue holds a run that failed or a
 source that has gone, orange where only the plan is at fault. A queue is read
 from the sidebar before its rows are, so it must not report a failure as
 mildly as a fixable plan.
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
      case .attention(let severity):
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(severity.tint)
          .accessibilityLabel(Text(label(for: severity)))
      case .done:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.secondary)
          .accessibilityLabel(Text("All done", bundle: #bundle))
      case .idle:
        EmptyView()
    }
  }

  /**
   What the triangle says aloud. Colour is the only thing separating the two
   tiers on screen, so it cannot be the only thing separating them in speech.
   */
  private func label(for severity: Severity) -> String {
    switch severity {
      case .problem: String(localized: "Has a problem", bundle: #bundle)
      case .warning, .note: String(localized: "Needs attention", bundle: #bundle)
    }
  }
}

#if DEBUG
  #Preview("Status Icons") {
    let states: [(String, QueueAggregateStatus)] = [
      ("Encoding", .running(0.6)),
      ("Problem", .attention(.problem)),
      ("Warning", .attention(.warning)),
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
