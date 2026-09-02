import AppKit
import Foundation
import os
import UserNotifications

/**
 Announces a finished run through Notification Center, so a batch left to run
 unattended says so when it lands.

 Owns the notification center and stands as its delegate for the lifetime of the
 app, which is why the ``Workspace`` it reports to holds it: the center's own
 `delegate` reference is weak.

 Built only from ``AppEnvironment/init(modelContainer:featureFlags:engine:updates:)``
 and only for a real run. `UNUserNotificationCenter.current()` raises in a
 process with no app bundle around it, which is exactly what the hostless unit
 test bundle is, and the authorization prompt is a system alert no XCUITest can
 dismiss.
 */
@MainActor
final class CompletionNotifier: NSObject, QueueCompletionReporting {

  private static let log = Logger(subsystem: "SubTrack", category: "CompletionNotifier")

  /// Identifies the one category, which carries the reveal action.
  nonisolated private static let categoryIdentifier = "codes.tim.SubTrack.runFinished"

  /// Identifies the reveal action within that category.
  nonisolated private static let revealActionIdentifier = "codes.tim.SubTrack.revealOutputs"

  /// Where the run's output paths travel in the notification's `userInfo`.
  nonisolated private static let outputPathsKey = "outputPaths"

  /// The one category: a finished run, with the option of revealing what it wrote.
  private static var runFinishedCategory: UNNotificationCategory {
    let reveal = UNNotificationAction(
      identifier: revealActionIdentifier,
      title: String(localized: "Reveal in Finder", bundle: #bundle),
      options: [.foreground]
    )
    return UNNotificationCategory(
      identifier: categoryIdentifier,
      actions: [reveal],
      intentIdentifiers: []
    )
  }

  private let center = UNUserNotificationCenter.current()

  /**
   The in-flight or settled authorization request, started by the first run and
   awaited by every notification. Held so the prompt is asked for once and so a
   grant that arrives after the run has ended still lets that run notify.
   */
  private var authorization: Task<Bool, Never>?

  override init() {
    super.init()
    center.delegate = self
    center.setNotificationCategories([Self.runFinishedCategory])
  }

  /**
   Asks for authorization, if this is the first run of the session. Deferring it
   to here rather than to launch means a user who never runs a queue is never
   asked, and the request is deliberately not awaited: the encode has no reason
   to wait on the prompt.
   */
  func queueWorkDidBegin() {
    guard authorization == nil else { return }
    authorization = Task { @MainActor in
      let granted = try? await self.center.requestAuthorization(options: [.alert, .sound])
      return granted ?? false
    }
  }

  /// Posts what the run came to, once the user has allowed it.
  func queueWorkDidFinish(_ summary: QueueRunSummary) {
    Task { @MainActor in
      guard await self.authorization?.value == true else { return }
      await self.post(summary)
    }
  }

  private func post(_ summary: QueueRunSummary) async {
    let content = UNMutableNotificationContent()
    content.title = title(for: summary)
    content.body = body(for: summary)
    content.sound = .default
    // Banners only show their buttons on hover, so the action is an extra, not
    // the point — and it's worth offering only when there is something to show.
    if !summary.outputURLs.isEmpty {
      content.categoryIdentifier = Self.categoryIdentifier
      content.userInfo = [
        Self.outputPathsKey: summary.outputURLs.map { $0.path(percentEncoded: false) }
      ]
    }
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    do {
      try await center.add(request)
    } catch {
      Self.log.warning(
        "Couldn’t post the finished-run notification: \(error.localizedDescription)"
      )
    }
  }

  /// The headline: whether the run got through its work.
  private func title(for summary: QueueRunSummary) -> String {
    if summary.finishedCount == 0 {
      return String(localized: "Slimming failed", bundle: #bundle)
    }
    if summary.failedCount > 0 {
      return String(localized: "Slimming finished with errors", bundle: #bundle)
    }
    return String(localized: "Slimming finished", bundle: #bundle)
  }

  /// What the run came to, written to stand on its own without the action button.
  private func body(for summary: QueueRunSummary) -> String {
    var sentences: [String] = []
    if summary.finishedCount > 0 { sentences.append(slimmedSentence(for: summary)) }
    if summary.failedCount > 0 {
      sentences.append(
        String(localized: "\(summary.failedCount) files failed.", bundle: #bundle)
      )
    }
    return sentences.joined(separator: " ")
  }

  /// How much the run slimmed, leaving the size out when nothing measured it.
  private func slimmedSentence(for summary: QueueRunSummary) -> String {
    let count = summary.finishedCount
    guard let bytesSaved = summary.bytesSaved, bytesSaved > 0 else {
      return String(localized: "Slimmed \(count) files.", bundle: #bundle)
    }
    let saved = bytesSaved.formatted(.byteCount(style: .file))
    return String(
      localized: "Slimmed \(count) files, saving \(saved).",
      bundle: #bundle
    )
  }

  /// Opens Finder on the run's outputs, skipping any that have since moved.
  private func revealOutputs(atPaths paths: [String]) {
    let urls = paths.map { URL(filePath: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }
}

/**
 `UNUserNotificationCenterDelegate` carries no isolation of its own, so its
 witnesses are `nonisolated` and hop to the main actor themselves. Each one
 takes the values it needs off the non-`Sendable` notification types before
 crossing.
 */
extension CompletionNotifier: UNUserNotificationCenterDelegate {
  /// Shows the banner even when SubTrack is frontmost, which macOS otherwise suppresses.
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }

  /// Handles the reveal action; a plain click just brings the app forward.
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard response.actionIdentifier == Self.revealActionIdentifier else { return }
    let paths = response.notification.request.content.userInfo[Self.outputPathsKey] as? [String]
    guard let paths else { return }
    await revealOutputs(atPaths: paths)
  }
}
