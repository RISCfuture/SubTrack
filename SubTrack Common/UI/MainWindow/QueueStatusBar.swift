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
      if let failure = env.storage.failure {
        PersistenceFailureIndicator(failure: failure)
      }
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
    var groups = [
      String(
        localized: "\(queue.items.count) items · \(queue.activeCount) encoding",
        bundle: #bundle
      )
    ]
    if queue.slimmedCount > 0 {
      groups.append(String(localized: "slimmed \(queue.slimmedCount) file", bundle: #bundle))
    }
    return groups.joined(separator: " · ")
  }
}

/**
 Shown only while the app is failing to record the user's work, and hidden
 entirely the moment a write succeeds — success needs no chrome, and this is
 the normal case by an overwhelming margin.

 It sits before the progress bar rather than at the very edge so that the bar,
 which the user watches, does not shift sideways the moment something goes
 wrong somewhere else.
 */
private struct PersistenceFailureIndicator: View {
  @Environment(\.openWindow)
  private var openWindow

  let failure: PersistenceError

  var body: some View {
    Button {
      openWindow(id: SubTrackWindowID.activity)
    } label: {
      Label {
        Text("Not saving", bundle: #bundle)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
      }
      .font(.callout)
      .foregroundStyle(Severity.problem.tint)
    }
    .buttonStyle(.plain)
    .help(summary)
    .accessibilityLabel(summary)
    .accessibilityIdentifier("status.persistenceFailure")
  }

  /**
   The headline and where to read the rest, but not the rest itself.
   ``PersistenceError/failureReason`` carries SwiftData's own account of the
   fault, which for a save conflict runs to kilobytes of object dump — right
   for the log and for the Activity Log, which wraps it and lets it be copied,
   and quite wrong for a tooltip.
   */
  private var summary: String {
    let detail = String(localized: "Open the Activity Log to read why.", bundle: #bundle)
    return [failure.errorDescription, detail].compactMap(\.self).joined(separator: " ")
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
      .accessibilityLabel(Text("Overall progress", bundle: #bundle))
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

  #Preview("Status bar — not saving") {
    let environment = PreviewSupport.environment(items: [
      PreviewSupport.ItemSpec(name: "A.mkv", status: .ready)
    ])
    environment.storage.record(
      .saveFailed(detail: "The file “Queues” couldn’t be opened."),
      from: .queues
    )
    return QueueStatusBar()
      .environment(environment)
      .frame(width: 640)
  }
#endif
