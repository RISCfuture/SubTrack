import SwiftUI

/**
 Progress for an in-flight ingest: a bar over the folder walk and the rows
 being added, with the file being handled beneath it.

 The bar runs indeterminate while scanning, because a folder tree's size
 isn't known until the walk ends.
 */
struct IngestProgressSheet: View {
  private static let sheetWidth: Double = 380

  let progress: IngestProgress
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading) {
      Text(title)
        .font(.headline)
      IngestProgressBar(progress: progress)
      Text(progress.currentName ?? "")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Spacer()
        Button(LocalizedStringResource("Cancel", bundle: #bundle), role: .cancel) { onCancel() }
          .accessibilityIdentifier("ingest.cancel")
      }
    }
    .padding()
    .frame(width: Self.sheetWidth)
    .accessibilityIdentifier("ingest.sheet")
  }

  private var title: String {
    switch progress.phase {
      case .scanning: String(localized: "Finding movies…", bundle: #bundle)
      case .adding: String(localized: "Adding to the queue…", bundle: #bundle)
    }
  }
}

/**
 The sheet's bar: determinate with a count once the total is known, and
 indeterminate while the folder walk is still discovering how much there is.
 */
private struct IngestProgressBar: View {
  let progress: IngestProgress

  var body: some View {
    if let fraction = progress.fraction, let total = progress.total {
      ProgressView(value: fraction) {
        EmptyView()
      } currentValueLabel: {
        Text("\(progress.completed, format: .number) of \(total, format: .number)", bundle: #bundle)
      }
    } else {
      ProgressView()
        .progressViewStyle(.linear)
    }
  }
}

#if DEBUG
  #Preview("Ingest — scanning") {
    let progress = IngestProgress()
    progress.beginScanning()
    progress.recordScanned(312)
    return IngestProgressSheet(progress: progress) {}
  }

  #Preview("Ingest — adding") {
    let progress = IngestProgress()
    progress.beginAdding(total: 512)
    for index in 1...312 { progress.recordAdded("Home with Kids S01E\(index).mkv") }
    return IngestProgressSheet(progress: progress) {}
  }
#endif
