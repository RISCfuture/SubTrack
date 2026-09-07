import SwiftUI

/**
 The file's Finder icon, its name, and the source path or error beneath.
 Missing sources are red; incompatible items are orange. Anything worth saying
 that falls short of those — a plan that would leave the output silent, say —
 follows the name as an info button carrying its explanation in a tooltip.
 Both text lines truncate to fit the column, so each carries its own tooltip
 holding the full string.
 The notice is handed in rather than read from the environment: a table cell
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
   Something about this item the reader would want to know but which does not
   make the item a problem — that the output would have no audio, say — or
   `nil` when there is nothing to say. ``QueueTableView`` supplies it.
   */
  var notice: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Self.lineSpacing) {
      HStack(spacing: Self.glyphSpacing) {
        FileTypeIcon(url: item.sourceURL)
        Text(item.displayName)
          .foregroundStyle(warningTint ?? .primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(item.displayName)
          .accessibilityIdentifier("queue.cell.name")
        // After the name rather than before it, and in `.secondary` rather than
        // a colour: this qualifies a row that is otherwise fine, and reading
        // louder than the status column's own glyphs would invert the two.
        if let visibleNotice {
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(visibleNotice)
            .accessibilityLabel(visibleNotice)
            .accessibilityIdentifier("queue.cell.notice")
        }
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
   The notice, withheld for an item already flagged by its status: a row whose
   subtitle is explaining why it failed has no room for a remark about how it
   would otherwise have turned out.
   */
  private var visibleNotice: String? {
    item.status.needsAttention ? nil : notice
  }

  /**
   The colour for the name and subtitle. Red is an item that cannot produce a
   file as it stands — its source is gone, or its run failed; orange is a plan
   at fault, which editing the rules would fix. Everything else takes the
   default primary/secondary shades.

   A failed run reads red rather than untinted so it is not the one error
   state drawn as though nothing were wrong, which is how it looked beside a
   missing source.
   */
  private var warningTint: Color? {
    switch item.status {
      case .missing, .failed: .red
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
        NameCell(item: $0, notice: environment.queue.audioLossWarning(for: $0))
      }
    } rows: {
      ForEach(environment.queue.items) { TableRow($0) }
    }
    .environment(environment)
    .frame(width: 420, height: 480)
  }
#endif
