import SwiftUI

/**
 What happened during this run of the app: the frame of each encoding run and
 everything that went wrong inside it, newest first.

 Newest first because the reason to open this window is that something has just
 happened, so the answer belongs at the top. There is no filter and nothing is
 dimmed: ``ActivityLog`` writes down only what is worth reading, so there is
 nothing here to hide. A file that inspects, encodes and finishes never reaches
 this table — the run's closing line carries the counts, and the queue window
 shows what each file came to.
 */
struct ActivityLogView: View {
  /// A time reads in one line; the room belongs to the message beside it.
  private static let timeColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (86, 96, 132)

  /// Queue names are short, and shorter than the messages they sit beside.
  private static let queueColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (80, 120, 180)

  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    Table(env.activity.events.reversed()) {
      TableColumn(LocalizedStringResource("Time", bundle: #bundle)) { event in
        TimestampCell(timestamp: event.timestamp)
      }
      .width(
        min: Self.timeColumnWidth.min,
        ideal: Self.timeColumnWidth.ideal,
        max: Self.timeColumnWidth.max
      )
      TableColumn(LocalizedStringResource("Queue", bundle: #bundle)) { event in
        WrappingCell(text: ActivityLogText.queue(event))
      }
      .width(
        min: Self.queueColumnWidth.min,
        ideal: Self.queueColumnWidth.ideal,
        max: Self.queueColumnWidth.max
      )
      TableColumn(LocalizedStringResource("File", bundle: #bundle)) { event in
        WrappingCell(text: event.fileName)
      }
      TableColumn(LocalizedStringResource("Event", bundle: #bundle)) { event in
        WrappingCell(text: ActivityLogText.event(event.kind))
          .foregroundStyle(event.kind.severity?.tint ?? .primary)
          .accessibilityIdentifier(ActivityLogText.identifier(event.kind))
      }
    }
    .accessibilityIdentifier("activity.table")
    .overlay {
      if env.activity.isEmpty { NothingHasHappenedYet() }
    }
  }
}

/// What each part of an event reads as, kept out of the view so it can be one thing.
private enum ActivityLogText {

  /// The queue an event is about, or that it is about all of them.
  static func queue(_ event: ActivityEvent) -> String {
    event.queueName.isEmpty ? String(localized: "All Queues", bundle: #bundle) : event.queueName
  }

  /// The sentence an event reads as.
  static func event(_ kind: ActivityEvent.Kind) -> String {
    switch kind {
      case .runStarted: String(localized: "Run started", bundle: #bundle)
      case let .runFinished(encoded, failed, cancelled, bytesSaved):
        runFinished(encoded: encoded, failed: failed, cancelled: cancelled, bytesSaved: bytesSaved)
      case .fileFailed(let message): String(localized: "Failed: \(message)", bundle: #bundle)
      case .sourceMissing: String(localized: "Source is missing", bundle: #bundle)
      case .incompatible(let reason): reason
      case .resolved: String(localized: "Problem cleared", bundle: #bundle)
      case .notSaving(let message): message
      case .savingAgain: String(localized: "Saving again", bundle: #bundle)
    }
  }

  /**
   How the UI tests find a line. Only the store's own trouble is addressed by
   name, because it is the only line a test asserts the presence of rather than
   the content of.
   */
  static func identifier(_ kind: ActivityEvent.Kind) -> String {
    if case .notSaving = kind { return "activity.persistenceFailure" }
    return "activity.event"
  }

  /**
   What a run came to, naming only the numbers that happened. A run with nothing
   cancelled says nothing about cancelling, so the common line stays short
   enough to take in at a glance.
   */
  private static func runFinished(
    encoded: Int,
    failed: Int,
    cancelled: Int,
    bytesSaved: Int?
  ) -> String {
    var parts = [String(localized: "\(encoded, format: .number) encoded", bundle: #bundle)]
    if failed > 0 {
      parts.append(String(localized: "\(failed, format: .number) failed", bundle: #bundle))
    }
    if cancelled > 0 {
      parts.append(String(localized: "\(cancelled, format: .number) cancelled", bundle: #bundle))
    }
    if let bytesSaved, bytesSaved > 0 {
      let saved = Int64(bytesSaved).formatted(.byteCount(style: .file))
      parts.append(String(localized: "\(saved) saved", bundle: #bundle))
    }
    let outcome = parts.formatted(.list(type: .and))
    return String(localized: "Run finished — \(outcome)", bundle: #bundle)
  }
}

/**
 When an event happened. A run left going overnight is read the morning after,
 so a bare time would be ambiguous the moment the app has been open past
 midnight — today's lines carry a time, and everything older carries its date
 as well.

 Monospaced digits so the column doesn't shimmer as the times change beneath
 it, and one line, because a time that wraps is a time that is too long.
 */
private struct TimestampCell: View {
  let timestamp: Date

  var body: some View {
    Text(timestamp, format: style)
      .monospacedDigit()
      .lineLimit(1)
      .textSelection(.enabled)
      .accessibilityLabel(Text(timestamp, format: .dateTime))
  }

  private var style: Date.FormatStyle {
    Calendar.current.isDateInToday(timestamp)
      ? .dateTime.hour().minute().second()
      : .dateTime.day().month(.abbreviated).hour().minute()
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

/**
 An empty log is the good outcome, so it says so rather than looking broken. It
 is also the common one: nothing here means no run has had any trouble.
 */
private struct NothingHasHappenedYet: View {
  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Nothing to report", bundle: #bundle)
      } icon: {
        Image(systemName: "checkmark.circle")
      }
    } description: {
      Text("Runs, and anything that goes wrong in them, will appear here.", bundle: #bundle)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .accessibilityIdentifier("activity.nothingToReport")
  }
}

#if DEBUG
  #Preview("An eventful run") {
    let environment = PreviewSupport.environment()
    PreviewSupport.recordEventfulRun(into: environment)
    return ActivityLogView()
      .environment(environment)
      .frame(minWidth: 760, minHeight: 340)
  }

  #Preview("Nothing to report") {
    ActivityLogView()
      .environment(PreviewSupport.environment())
      .frame(minWidth: 760, minHeight: 240)
  }
#endif
