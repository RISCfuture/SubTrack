import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
  /// The private drag type used to reorder queue rows within the app.
  static let subTrackQueueItem = UTType(exportedAs: "com.subtrack.queue-item")
}

/**
 The payload dragged when a queue row is reordered: just the row's identity.
 Its private content type keeps drops confined to reordering within the app.
 */
struct QueueItemDragPayload: Codable, Transferable {
  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .subTrackQueueItem)
  }

  let id: UUID
}
