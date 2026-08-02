import SwiftUI

/**
 The file's Finder icon, its name, and the source path or error beneath.
 Missing sources are red; incompatible items are orange. A plan that would
 leave the output silent adds a caution icon between the icon and the name.
 Both text lines truncate to fit the column, so each carries its own tooltip
 holding the full string.
 The warning is handed in rather than read from the environment: a table cell
 is laid out again while its row is being removed, and reading a non-optional
 `@Environment` observable at that moment traps.
 */
struct NameCell: View {
  /**
   The name and its subtitle sit tighter than default spacing so the pair reads
   as one row rather than two.
   */
  private static let lineSpacing: Double = 1

  /// Keeps the icon and caution glyph hugging the name they qualify.
  private static let glyphSpacing: Double = 4

  let item: QueueItem

  /**
   Why this item's output would have no audio, or `nil` when it would.
   ``QueueTableView`` supplies it, already withheld for items whose status
   carries its own warning.
   */
  var audioWarning: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Self.lineSpacing) {
      HStack(spacing: Self.glyphSpacing) {
        FileTypeIcon(url: item.sourceURL)
        if let audioLossWarning {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help(audioLossWarning)
            .accessibilityLabel(audioLossWarning)
            .accessibilityIdentifier("queue.cell.audioWarning")
        }
        Text(item.displayName)
          .foregroundStyle(warningTint ?? .primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(item.displayName)
          .accessibilityIdentifier("queue.cell.name")
      }
      if let subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(warningTint ?? .secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(subtitle)
      }
    }
  }

  /**
   The audio-loss warning, withheld for an item already flagged by its status
   so a row never carries two competing signals.
   */
  private var audioLossWarning: String? {
    item.status.needsAttention ? nil : audioWarning
  }

  /**
   The color for the name and subtitle in the two exceptional states, or
   `nil` for the default primary/secondary shades.
   */
  private var warningTint: Color? {
    switch item.status {
      case .missing: .red
      case .incompatible: .orange
      default: nil
    }
  }

  private var subtitle: String? {
    switch item.status {
      case .missing: String(localized: "Source is missing", bundle: #bundle)
      case .incompatible(let reason): reason
      case .failed(let message): message
      default: item.sourceURL.deletingLastPathComponent().path(percentEncoded: false)
    }
  }
}

#if DEBUG
  #Preview("Name Cell — states") {
    let items =
      PreviewSupport.everyStatusItems() + [
        PreviewSupport.ItemSpec(
          name: "Foreign.mkv",
          status: .ready,
          container: PreviewSupport.container(
            audio: [PreviewSupport.AudioTrack(codec: "aac", language: "jpn", channels: 2)]
          )
        )
      ]
    let environment = PreviewSupport.environment(items: items)
    return Table(of: QueueItem.self) {
      TableColumn(LocalizedStringResource("Name", bundle: #bundle)) {
        NameCell(item: $0, audioWarning: environment.queue.audioLossWarning(for: $0))
      }
    } rows: {
      ForEach(environment.queue.items) { TableRow($0) }
    }
    .environment(environment)
    .frame(width: 420, height: 480)
  }
#endif
