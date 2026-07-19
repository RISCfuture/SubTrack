import SwiftUI

/**
 How many tracks the output holds: what the finished run left behind, or —
 until it runs — how many the current rules plan to keep.
 */
struct OutputTracksCell: View {
  @Environment(AppEnvironment.self)
  private var env
  let item: QueueItem

  var body: some View {
    MetricCell(text: env.queue.outputTrackCount(for: item)?.formatted(.number))
      .accessibilityIdentifier("queue.cell.outputTracks")
  }
}
