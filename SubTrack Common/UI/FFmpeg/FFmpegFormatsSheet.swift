import SwiftUI

/**
 Presents ``FFmpegFormatsView`` in a sheet, reflecting the probe lifecycle:
 a spinner while reading, a message if the build can't be run, and the
 grouped list once loaded.
 */
struct FFmpegFormatsSheet: View {
  @Environment(\.dismiss)
  private var dismiss
  let store: FFmpegCapabilitiesStore
  var showsFullVersionLink = false

  var body: some View {
    NavigationStack {
      Group {
        switch store.state {
          case .loaded(let capabilities):
            FFmpegFormatsView(
              capabilities: capabilities,
              showsFullVersionLink: showsFullVersionLink
            )
          case .unavailable(let reason):
            ContentUnavailableView {
              Label(
                LocalizedStringResource("FFmpeg Unavailable", bundle: #bundle),
                systemImage: "exclamationmark.triangle"
              )
            } description: {
              Text(reason)
            } actions: {
              HelpTopicButton(
                anchor: .customFFmpeg,
                accessibilityIdentifier: "formats.unavailableHelp"
              )
            }
          case .idle, .loading:
            ProgressView("Reading ffmpeg…")
        }
      }
      .toolbar {
        ToolbarItem {
          HelpTopicLink(anchor: .supportedFormats, accessibilityIdentifier: "formats.help")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(LocalizedStringResource("Done", bundle: #bundle)) { dismiss() }
        }
      }
    }
    .frame(minWidth: 480, minHeight: 520)
  }
}

#if DEBUG
  #Preview("Sheet — loaded") {
    FFmpegFormatsSheet(store: FFmpegCapabilitiesStore(state: .loaded(.previewSample)))
  }

  #Preview("Sheet — unavailable") {
    FFmpegFormatsSheet(
      store: FFmpegCapabilitiesStore(state: .unavailable("ffmpeg could not be found"))
    )
  }

  #Preview("Sheet — loading") {
    FFmpegFormatsSheet(store: FFmpegCapabilitiesStore(state: .loading))
  }
#endif
