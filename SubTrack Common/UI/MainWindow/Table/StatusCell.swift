import SwiftUI

/**
 The queue's single status indicator: nothing while an item is pending, a
 progress ring while a step runs (indeterminate until `ffmpeg` reports a
 fraction, then determinate), a checkmark when finished, and a warning
 triangle on error. Everything reads in `.secondary` — no status color.
 */
struct StatusCell: View {
  let item: QueueItem

  var body: some View {
    switch item.status {
      case .waiting, .ready, .cancelled:
        EmptyView()
      case .probing:
        StatusRing(fraction: nil, help: helpText, identifier: "queue.status.probing")
      case .running:
        StatusRing(
          fraction: item.progress > 0 ? item.progress : nil,
          help: helpText,
          identifier: "queue.status.running"
        )
      case .done:
        StatusGlyph(
          systemName: "checkmark.circle.fill",
          help: helpText,
          identifier: "queue.status.done"
        )
      case .missing:
        StatusGlyph(
          systemName: "exclamationmark.triangle.fill",
          help: helpText,
          identifier: "queue.status.missing"
        )
      case .incompatible:
        StatusGlyph(
          systemName: "exclamationmark.triangle.fill",
          help: helpText,
          identifier: "queue.status.incompatible"
        )
      case .failed:
        StatusGlyph(
          systemName: "exclamationmark.triangle.fill",
          help: helpText,
          identifier: "queue.status.failed"
        )
    }
  }

  private var helpText: String {
    switch item.status {
      case .waiting: String(localized: "Waiting")
      case .probing: String(localized: "Inspecting")
      case .ready: String(localized: "Ready")
      case .running: String(localized: "Encoding")
      case .done: String(localized: "Done")
      case .cancelled: String(localized: "Cancelled")
      case .missing: String(localized: "Source is missing")
      case .incompatible(let reason): reason
      case .failed(let message): message
    }
  }
}

/**
 A small circular progress ring drawn in `.secondary`; a `nil` fraction spins
 indeterminately, a `0...1` fraction fills the ring.
 */
private struct StatusRing: View {
  let fraction: Double?
  let help: String
  let identifier: String

  var body: some View {
    ProgressView(value: fraction)
      .progressViewStyle(.circular)
      .controlSize(.small)
      .tint(.secondary)
      .help(help)
      .accessibilityLabel(help)
      .accessibilityIdentifier(identifier)
  }
}

/// A monochrome status glyph drawn in `.secondary`, with a tooltip and label.
private struct StatusGlyph: View {
  let systemName: String
  let help: String
  let identifier: String

  var body: some View {
    Image(systemName: systemName)
      .foregroundStyle(.secondary)
      .help(help)
      .accessibilityLabel(help)
      .accessibilityIdentifier(identifier)
  }
}

#if DEBUG
  /// Renders the status/name cells across every lifecycle state for previewing.
  struct StatusCellGallery: View {
    private let states: [QueueItemState] = [
      .waiting,
      .probing,
      .ready,
      .running,
      .done,
      .cancelled,
      .missing,
      .incompatible("The “libx265” encoder isn’t available in the current FFmpeg"),
      .failed("ffmpeg exited with code 1")
    ]

    var body: some View {
      Form {
        ForEach(Array(states.enumerated()), id: \.offset) { _, status in
          LabeledContent {
            NameCell(item: item(status))
          } label: {
            StatusCell(item: item(status))
          }
        }
      }
      .formStyle(.grouped)
      .frame(width: 360)
    }

    private func item(_ status: QueueItemState) -> QueueItem {
      let item = QueueItem(
        sourceURL: URL(filePath: "/Movies/Clip.mkv"),
        outputURL: URL(filePath: "/Movies/Clip (slimmed).mkv")
      )
      item.status = status
      // Give the running row a determinate ring; the indeterminate spinner is
      // covered by the probing row.
      if status == .running { item.progress = 0.6 }
      return item
    }
  }

  #Preview("Status & Name Cells") {
    StatusCellGallery()
  }
#endif
