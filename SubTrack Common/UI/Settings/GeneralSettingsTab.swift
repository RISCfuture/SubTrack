import SwiftUI

/**
 The default output destination new queues inherit; each queue's own
 destination is set from its window.
 */
struct GeneralSettingsTab: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Default destination")
      HStack(spacing: 12) {
        Text(
          env.defaultDestination.destinationURL?.path(percentEncoded: false)
            ?? String(localized: "Next to each source")
        )
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        Spacer(minLength: 0)
        Button("Change Destination…") {
          if let url = FilePanels.chooseDestination() { env.defaultDestination.setDestination(url) }
        }
        .accessibilityIdentifier("settings.generalDestination")
      }
      Text("New queues start here. Each queue’s own destination is set from its window.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#if DEBUG
  #Preview("General Tab") {
    GeneralSettingsTab()
      .environment(settingsPreviewEnvironment(isAppStoreBuild: false))
      .frame(width: 480, height: 300)
  }

  #Preview("General Tab — destination set") {
    let env = settingsPreviewEnvironment(isAppStoreBuild: false)
    env.defaultDestination.setDestination(URL(filePath: "/Users/Shared/Movies"))
    return GeneralSettingsTab()
      .environment(env)
      .frame(width: 480, height: 300)
  }
#endif
