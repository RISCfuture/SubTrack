import SwiftUI

/**
 A simple activity view listing each item's status and any error, for
 troubleshooting. Every column truncates to fit, so each cell carries a
 tooltip holding the full string.
 */
struct ActivityLogView: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    Table(env.queue.items) {
      TableColumn(LocalizedStringResource("File", bundle: #bundle)) { item in
        Text(item.displayName)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(item.displayName)
      }
      TableColumn(LocalizedStringResource("Status", bundle: #bundle)) { item in
        Text(statusText(item))
          .foregroundStyle(color(item))
          .lineLimit(1)
          .truncationMode(.tail)
          .help(statusText(item))
      }
      TableColumn(LocalizedStringResource("Output", bundle: #bundle)) { item in
        Text(item.outputURL.path(percentEncoded: false))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(item.outputURL.path(percentEncoded: false))
      }
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

  private func color(_ item: QueueItem) -> Color {
    switch item.status {
      case .failed, .missing: .red
      default: .secondary
    }
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
