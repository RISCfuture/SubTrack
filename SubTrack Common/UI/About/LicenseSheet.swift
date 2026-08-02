import SwiftUI

/**
 A sheet presenting the full license text of the build's
 ``FFmpegAcknowledgement``, opened from the About window.
 */
struct LicenseSheet: View {
  @Environment(\.dismiss)
  private var dismiss
  let acknowledgement: FFmpegAcknowledgement

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(acknowledgement.licenseBody)
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding()
      }
      .navigationTitle(acknowledgement.licenseTitle)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(LocalizedStringResource("Done", bundle: #bundle)) { dismiss() }
        }
      }
    }
    .frame(width: 460, height: 420)
  }
}

#if DEBUG
  #Preview("License — GPL") {
    LicenseSheet(acknowledgement: .gpl)
  }

  #Preview("License — LGPL") {
    LicenseSheet(acknowledgement: .lgpl)
  }
#endif
