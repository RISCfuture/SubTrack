import SwiftUI

/**
 A table of everything the app has to say about the work in front of it: every
 queued file across every queue, and the conditions that belong to no file at
 all.

 The columns wrap rather than truncate. A failure message carries its recovery
 suggestion at the end — the fix to try, or where a finished file was left —
 so the tail of the string is the half worth reading, and abbreviating a cell
 would take exactly that.
 */
struct ActivityLogView: View {
  /// Queue names are short; the room belongs to the message beside them.
  private static let queueColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (80, 120, 180)

  @Environment(AppEnvironment.self)
  private var env

  /**
   Whatever is worth saying, the app-wide conditions first — a store that
   cannot be written is the reason a file's own line may be the last true
   thing said about it — and then each queue's files in sidebar order.
   */
  private var entries: [ActivityLogEntry] {
    let conditions = env.storage.activeFailures.enumerated().map {
      ActivityLogEntry.everyQueue($0.element, rank: $0.offset)
    }
    let files = env.workspace.coordinators.flatMap { coordinator in
      coordinator.items.map { ActivityLogEntry.queued($0, queueName: coordinator.name) }
    }
    return conditions + files
  }

  var body: some View {
    Table(entries) {
      TableColumn(LocalizedStringResource("Queue", bundle: #bundle)) { entry in
        WrappingCell(text: entry.queueName)
      }
      .width(
        min: Self.queueColumnWidth.min,
        ideal: Self.queueColumnWidth.ideal,
        max: Self.queueColumnWidth.max
      )
      TableColumn(LocalizedStringResource("File", bundle: #bundle)) { entry in
        WrappingCell(text: entry.subject)
          .accessibilityIdentifier(entry.accessibilityIdentifier)
      }
      TableColumn(LocalizedStringResource("Status", bundle: #bundle)) { entry in
        WrappingCell(text: entry.status)
          .foregroundStyle(entry.tint)
      }
      TableColumn(LocalizedStringResource("Output", bundle: #bundle)) { entry in
        WrappingCell(text: entry.output)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("activity.table")
  }
}

/**
 One line of the table: a file in one of the queues, or a condition that is
 true of all of them at once.

 Both kinds answer the same four questions, which is what lets them share the
 columns — a persistence failure is not about a file, but it is very much
 about a queue, and saying so is the whole point of putting it here.
 */
@MainActor
private enum ActivityLogEntry: Identifiable {
  /// A file waiting in, running in, or finished in the named queue.
  case queued(QueueItem, queueName: String)

  /**
   A read or write of the app's own stored data that failed, so it is true of
   every queue. `rank` distinguishes the two that can stand at once.
   */
  case everyQueue(PersistenceError, rank: Int)

  var id: String {
    switch self {
      case .queued(let item, _): "file.\(item.id)"
      case .everyQueue(_, let rank): "everyQueue.\(rank)"
    }
  }

  /// Which queue this line is about, or that it is about all of them.
  var queueName: String {
    switch self {
      case .queued(_, let queueName): queueName
      case .everyQueue: String(localized: "All Queues", bundle: #bundle)
    }
  }

  /// What the line is about: a file, or the condition standing in for one.
  var subject: String {
    switch self {
      case .queued(let item, _): item.displayName
      case .everyQueue: String(localized: "Not saving", bundle: #bundle)
    }
  }

  /// How it went, at whatever length it takes to say so.
  var status: String {
    switch self {
      case .queued(let item, _): Self.statusText(item)
      case .everyQueue(let failure, _): failure.userMessage
    }
  }

  /// Where the file goes. A failure to save produced no file, and says so by
  /// leaving the column empty rather than filling it with a dash.
  var output: String {
    switch self {
      case .queued(let item, _): item.outputURL.path(percentEncoded: false)
      case .everyQueue: ""
    }
  }

  /**
   The one severity vocabulary the queue table also reads from, so an item
   cannot change tier depending on which window it is shown in. A store that
   will not accept the user's work is a problem by any reading.
   */
  var tint: Color {
    switch self {
      case .queued(let item, _): (item.status.severity ?? .note).tint
      case .everyQueue: Severity.problem.tint
    }
  }

  /// How the UI tests find this line.
  var accessibilityIdentifier: String {
    switch self {
      case .queued(let item, _): "activity.file.\(item.id)"
      case .everyQueue: "activity.persistenceFailure"
    }
  }

  private static func statusText(_ item: QueueItem) -> String {
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
}

/**
 One cell, wrapping to its content and selectable so a message can be pasted
 into a bug report rather than retyped. Growing vertically is the whole reason
 this window is worth opening, so the text is fixed against the vertical
 squeeze a table row would otherwise apply to it.
 */
private struct WrappingCell: View {
  let text: String

  var body: some View {
    Text(text)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if DEBUG
  #Preview("All statuses") {
    ActivityLogView()
      .environment(PreviewSupport.environment(items: PreviewSupport.everyStatusItems()))
      .frame(minWidth: 720, minHeight: 340)
  }

  #Preview("Not saving") {
    let environment = PreviewSupport.environment(items: PreviewSupport.everyStatusItems())
    environment.storage.record(
      .saveFailed(detail: "The file “Queues” couldn’t be opened."),
      from: .queues
    )
    return ActivityLogView()
      .environment(environment)
      .frame(minWidth: 720, minHeight: 340)
  }

  #Preview("Empty") {
    ActivityLogView()
      .environment(PreviewSupport.environment())
      .frame(minWidth: 720, minHeight: 240)
  }
#endif
