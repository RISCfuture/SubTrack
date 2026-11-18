import SwiftUI

/**
 How many tracks the output holds: what the finished run left behind, or —
 until it runs — how many the current rules plan to keep.
 */
struct OutputTracksCell: View {
  let item: QueueItem
  let queue: QueueCoordinator

  var body: some View {
    MetricCell(text: queue.outputTrackCount(for: item)?.formatted(.number))
      .accessibilityIdentifier("queue.cell.outputTracks")
  }
}
