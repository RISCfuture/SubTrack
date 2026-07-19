import SwiftUI

/// The output destination folder and a control to change it.
struct DestinationBar: View {
  @Environment(AppEnvironment.self)
  private var env

  var body: some View {
    HStack {
      Label {
        Text(destinationLabel)
          .foregroundStyle(env.destination.destinationURL == nil ? .secondary : .primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("destination.path")
      } icon: {
        Image(systemName: "folder")
      }
      Text("· names look like “\(env.queue.settings.naming.sampleFileName)”")
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Button("Change…") { chooseDestination() }
        .accessibilityIdentifier("destination.change")
    }
    .windowBarInsets()
  }

  private var destinationLabel: String {
    env.destination.destinationURL?.path(percentEncoded: false)
      ?? String(localized: "Saves next to each source")
  }

  private func chooseDestination() {
    if let url = FilePanels.chooseDestination() { env.destination.setDestination(url) }
  }
}

#if DEBUG
  #Preview("Destination bar") {
    let withDestination = PreviewSupport.environment()
    withDestination.destination.setDestination(URL(filePath: "/Users/Shared/Movies"))
    return VStack(spacing: 0) {
      DestinationBar()
        .environment(PreviewSupport.environment())
      Divider()
      DestinationBar()
        .environment(withDestination)
    }
    .frame(width: 640)
    .padding()
  }
#endif
