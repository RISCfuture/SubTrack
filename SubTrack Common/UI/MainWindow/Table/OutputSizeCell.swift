import SwiftUI

/**
 The output file's size, measured once the item has finished. Until then it's
 the size the run is projected to produce, marked with a tilde so a prediction
 never reads as a fact.
 */
struct OutputSizeCell: View {
  @Environment(AppEnvironment.self)
  private var env
  let item: QueueItem

  var body: some View {
    MetricCell(text: text)
      .accessibilityIdentifier("queue.cell.outputSize")
  }

  private var text: String? {
    guard let size = env.queue.outputSize(for: item) else { return nil }
    let byteCount = size.byteCount.formatted(.byteCount(style: .file))
    guard size.isEstimate else { return byteCount }
    return String(
      localized: "~\(byteCount)",
      comment: "An estimated output file size, e.g. “~1.2 GB”. The argument is the formatted size."
    )
  }
}

#if DEBUG
  // "Ready" and "Encoding" have a probed container but no measured output, so
  // they show the tilde-marked estimate; "Done" carries a real output size and
  // shows it unmarked. The rest have neither and fall back to the em dash.
  #Preview("Output Size Cell") {
    let environment = PreviewSupport.environment(items: PreviewSupport.everyStatusItems())
    return Table(of: QueueItem.self) {
      TableColumn("Name") { Text($0.displayName) }
        .width(min: 140)
      TableColumn("Output Size") { OutputSizeCell(item: $0) }
        .width(min: 65, ideal: 95, max: 95)
    } rows: {
      ForEach(environment.queue.items) { TableRow($0) }
    }
    .environment(environment)
    .frame(width: 340, height: 320)
  }
#endif
