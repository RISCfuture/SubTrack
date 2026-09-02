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
   The authorization request now on screen, or `nil` when none is. Awaited by a
   notification whose run ended while the prompt was still up, so a grant that
   arrives late still lets that run notify.
   */
  private var authorizationRequest: Task<Bool, Never>?

  /// Whether the user allowed notifications, as of the last time we asked.
  private var isAuthorized = false

  /// Whether notifications are allowed, waiting on a prompt still on screen.
  private var isAllowedToNotify: Bool {
    get async {
      if let authorizationRequest { return await authorizationRequest.value }
      return isAuthorized
    }
  }

  override init() {
    super.init()
    center.delegate = self
    center.setNotificationCategories([Self.runFinishedCategory])
  }

  /**
   Asks for authorization, unless it is already granted or already being asked
   for. Deferring it to here rather than to launch means a user who never runs a
   queue is never asked, and the request is deliberately not awaited: the encode
   has no reason to wait on the prompt.

   A refusal is not remembered for the session. macOS answers a repeat request
   from its stored decision without putting the prompt up a second time, so
   asking again on the next run is what picks up a user who turned notifications
   on in System Settings after having turned them down here.
   */
  func queueWorkDidBegin() {
    guard !isAuthorized, authorizationRequest == nil else { return }
    authorizationRequest = Task { @MainActor in
      let granted = try? await self.center.requestAuthorization(options: [.alert, .sound])
      self.isAuthorized = granted ?? false
      self.authorizationRequest = nil
      return self.isAuthorized
    }
  }

  /// Posts what the run came to, once the user has allowed it.
  func queueWorkDidFinish(_ summary: QueueRunSummary) {
    Task { @MainActor in
      guard await self.isAllowedToNotify else { return }
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

  /**
   Opens Finder on the run's outputs, leaving Finder itself to pass over
   anything that has since moved.

   The paths are deliberately not checked first: the app is sandboxed and the
   security-scoped access the run held over the output folder ended with the
   run, so asking the file manager about them here reports every output outside
   the container missing and reveals nothing at all.
   */
  private func revealOutputs(atPaths paths: [String]) {
    NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(filePath: $0) })
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
