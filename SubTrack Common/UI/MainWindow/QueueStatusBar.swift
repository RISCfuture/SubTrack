import SwiftUI

/**
 The bottom status summary, joined while work is in flight by a queue-wide
 progress bar.
 */
struct QueueStatusBar: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    HStack {
      Text(summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("status.summary")
      if env.queue.isRunning {
        OverallProgressBar(fraction: env.queue.overallProgress)
      }
    }
    .windowBarInsets()
  }

  /**
   The whole summary as one middle-dot-separated string, so every segment —
   including the optional slimming outcome — is spaced identically.
   */
  private var summary: String {
    let queue = env.queue
    var groups = [String(localized: "\(queue.items.count) items · \(queue.activeCount) encoding")]
    if queue.slimmedCount > 0 {
      groups.append(String(localized: "slimmed \(queue.slimmedCount) file"))
    }
    return groups.joined(separator: " · ")
  }
}

/**
 How far the queue as a whole has got. Sized against the body text so it keeps
 its proportions as type scales.
 */
private struct OverallProgressBar: View {
  @ScaledMetric private var width: Double = 140
  let fraction: Double

  var body: some View {
    ProgressView(value: fraction)
      .progressViewStyle(.linear)
      .frame(width: width)
      .accessibilityLabel("Overall progress")
      .accessibilityIdentifier("status.overallProgress")
  }
}

#if DEBUG
  #Preview("Status bar") {
    VStack(spacing: 0) {
      QueueStatusBar()
        .environment(PreviewSupport.environment())
      Divider()
      QueueStatusBar()
        .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
      Divider()
      QueueStatusBar()
        .environment(
          PreviewSupport.environment(items: [
            PreviewSupport.ItemSpec(name: "A.mkv", status: .ready),
            PreviewSupport.ItemSpec(name: "B.mkv", status: .ready)
          ])
        )
    }
    .frame(width: 640)
  }
#endif
