import AppKit
import SwiftUI
import UniformTypeIdentifiers

/**
 The Finder document icon for a queued file, sized to sit beside its name.

 Decorative: the file name reads immediately after it, so the icon is hidden
 from accessibility rather than repeating that name.
 */
struct FileTypeIcon: View {
  @ScaledMetric(relativeTo: .body)
  private var side = 16
  let url: URL

  var body: some View {
    Image(nsImage: FileIconCache.icon(for: url))
      .resizable()
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

/**
 Finder document icons, remembered per file extension.

 A queue holding a season of one show is hundreds of rows of a single type,
 and `NSWorkspace.icon(forFile:)` reads the file itself — far too slow to run
 per row while scrolling. Keying on the extension resolves one icon per type
 instead, and asking for the *type's* icon needs no disk access at all.
 */
@MainActor
enum FileIconCache {
  private static var iconsByExtension: [String: NSImage] = [:]

  /**
   The icon for `url`'s file type, falling back to the generic document icon
   when the extension names no type the system knows.
   */
  static func icon(for url: URL) -> NSImage {
    let fileExtension = url.pathExtension.lowercased()
    if let cached = iconsByExtension[fileExtension] { return cached }
    let type = UTType(filenameExtension: fileExtension) ?? .data
    let icon = NSWorkspace.shared.icon(for: type)
    iconsByExtension[fileExtension] = icon
    return icon
  }
}

#if DEBUG
  #Preview("File Type Icons") {
    VStack(alignment: .leading) {
      FileTypeIcon(url: URL(filePath: "/m.mkv"))
      FileTypeIcon(url: URL(filePath: "/m.mp4"))
      FileTypeIcon(url: URL(filePath: "/m.unknownextension"))
    }
    .padding()
  }
#endif
