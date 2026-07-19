import SwiftUI

/// How many encodes run at once, and which codec set this build ships with.
struct EncodingSettingsTab: View {
  /**
   How many encodes to allow at once. Steps rather than every number in a
   range: the choice is roughly "one at a time", "a couple", or "saturate the
   machine", and the values between make no difference worth offering.
   */
  private static let concurrencyChoices = [1, 2, 3, 4, 6, 8]

  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    @Bindable var queue = env.queue
    Form {
      Picker("Simultaneous encodes", selection: $queue.maxConcurrent) {
        ForEach(Self.concurrencyChoices, id: \.self) { choice in
          Text(choice, format: .number).tag(choice)
        }
      }
      .accessibilityIdentifier("settings.maxConcurrent")
      LabeledContent("Codec set") {
        HStack(spacing: 6) {
          Text(
            env.featureFlags.fullCodecSet
              ? String(localized: "Full (all codecs)")
              : String(localized: "App Store (VideoToolbox)")
          )
          .foregroundStyle(.secondary)
          if env.featureFlags.isAppStoreBuild { FullVersionHelpLink() }
        }
      }
    }
    .formStyle(.grouped)
  }
}

#if DEBUG
  #Preview("Encoding Tab — full (download)") {
    EncodingSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
      .frame(width: 480, height: 260)
  }

  #Preview("Encoding Tab — App Store (gated)") {
    EncodingSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: true))
      .frame(width: 480, height: 260)
  }
#endif
