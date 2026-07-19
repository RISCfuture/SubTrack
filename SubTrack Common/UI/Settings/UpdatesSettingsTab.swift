import SwiftUI

/**
 How often the downloadable build looks for a new release, and the controls to
 check right now or reconsider a skipped version. Absent from the App Store
 build, which the store keeps current.
 */
struct UpdatesSettingsTab: View {
  let updates: any UpdateChecking

  var body: some View {
    Form {
      Picker("Check for updates", selection: cadence) {
        ForEach(UpdateCheckCadence.allCases) { choice in
          Text(choice.label).tag(choice)
        }
      }
      .accessibilityIdentifier("settings.updateCadence")
      Toggle("Include prerelease versions", isOn: includesPrereleases)
        .accessibilityIdentifier("settings.updatePrereleases")
      LabeledContent("Last checked") {
        LastCheckedLabel(date: updates.lastCheckDate)
      }
      HStack {
        Button("Check Now") {
          Task { await updates.checkForUpdatesAndShowUI() }
        }
        .disabled(!updates.canCheckForUpdates)
        .accessibilityIdentifier("settings.checkForUpdates")
        Spacer(minLength: 0)
        Button("Reset Skipped Versions") { updates.resetSkippedVersions() }
          .disabled(!updates.hasSkippedVersions)
          .accessibilityIdentifier("settings.resetSkippedVersions")
      }
    }
    .formStyle(.grouped)
  }

  @MainActor private var cadence: Binding<UpdateCheckCadence> {
    Binding {
      updates.cadence
    } set: {
      updates.cadence = $0
    }
  }

  @MainActor private var includesPrereleases: Binding<Bool> {
    Binding {
      updates.includesPrereleases
    } set: {
      updates.includesPrereleases = $0
    }
  }
}

/// When the last check ran, or a dash before the first one has.
private struct LastCheckedLabel: View {
  let date: Date?

  var body: some View {
    Group {
      if let date {
        Text(date, format: .relative(presentation: .named))
      } else {
        Text(verbatim: "—")
      }
    }
    .foregroundStyle(.secondary)
  }
}

#if DEBUG
  /// A canned ``UpdateChecking`` so the Settings previews can show the tab.
  @MainActor
  @Observable
  final class StubUpdateChecker: UpdateChecking {
    var canCheckForUpdates = true
    var lastCheckDate: Date?
    var cadence = UpdateCheckCadence.daily
    var includesPrereleases = false
    var hasSkippedVersions = false

    init(lastCheckDate: Date? = nil, hasSkippedVersions: Bool = false) {
      self.lastCheckDate = lastCheckDate
      self.hasSkippedVersions = hasSkippedVersions
    }

    // The protocol requires `async`; a stub has nothing to await.
    // swiftlint:disable:next async_without_await
    func checkForUpdatesAndShowUI() async {}

    func resetSkippedVersions() { hasSkippedVersions = false }
  }

  #Preview("Updates Tab — checked") {
    UpdatesSettingsTab(
      updates: StubUpdateChecker(
        lastCheckDate: Date(timeIntervalSinceNow: -3600),
        hasSkippedVersions: true
      )
    )
    .frame(width: 480, height: 260)
  }

  #Preview("Updates Tab — never checked") {
    UpdatesSettingsTab(updates: StubUpdateChecker())
      .frame(width: 480, height: 260)
  }
#endif
