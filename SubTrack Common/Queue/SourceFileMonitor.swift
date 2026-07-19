import Foundation

/**
 Watches a source file (and its containing folder) and invokes `onChange`
 when the file appears, disappears, or is modified — so the queue can flip
 items to and from `.missing` without a manual refresh.

 The folder watch catches re-creation after the file source's descriptor is
 invalidated by a delete, so no manual re-arming is needed.
 */
final class SourceFileMonitor {
  private var sources: [DispatchSourceFileSystemObject] = []

  /**
   Starts watching `url` and its folder, calling `onChange` on the main actor
   for every event. Watching stops when the monitor is released.
   */
  init(url: URL, onChange: @escaping @MainActor () -> Void) {
    let notify: @Sendable () -> Void = { Task { @MainActor in onChange() } }

    if let fileSource = Self.makeSource(
      path: url.path(percentEncoded: false),
      mask: [.delete, .rename, .write, .extend],
      onEvent: notify
    ) {
      sources.append(fileSource)
    }

    if let folderSource = Self.makeSource(
      path: url.deletingLastPathComponent().path(percentEncoded: false),
      mask: [.write],
      onEvent: notify
    ) {
      sources.append(folderSource)
    }
  }

  private static func makeSource(
    path: String,
    mask: DispatchSource.FileSystemEvent,
    onEvent: @escaping @Sendable () -> Void
  ) -> DispatchSourceFileSystemObject? {
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { return nil }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: mask,
      queue: DispatchQueue(label: "codes.tim.SubTrack.SourceFileMonitor", qos: .utility)
    )
    source.setEventHandler(handler: onEvent)
    source.setCancelHandler { close(descriptor) }
    source.resume()
    return source
  }

  deinit {
    for source in sources { source.cancel() }
  }
}
