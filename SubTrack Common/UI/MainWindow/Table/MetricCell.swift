import SwiftUI

/**
 A single number in the queue table — a track count or a byte size — shown in
 the table's secondary shade, or as an em dash when the value isn't known.
 */
struct MetricCell: View {
  let text: String?

  var body: some View {
    Text(text ?? "—")
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
  }
}

#if DEBUG
  #Preview("Metric Cell") {
    VStack(alignment: .leading) {
      MetricCell(text: 7.formatted(.number))
      MetricCell(text: 1234.formatted(.number))
      MetricCell(text: 1_800_000_000.formatted(.byteCount(style: .file)))
      MetricCell(text: nil)
    }
    .padding()
  }
#endif
