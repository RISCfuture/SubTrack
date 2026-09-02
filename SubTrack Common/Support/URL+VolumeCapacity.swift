import Foundation

extension URL {
  /**
   How many bytes this URL's volume can give to something the user is waiting
   on, or `nil` when the volume won't say.

   On APFS the system counts space it would purge to satisfy the request, so
   the answer is larger than the free space Finder reports and is the number a
   preflight should compare against — asking for the raw free space would
   refuse writes that would in fact have succeeded. A volume that keeps no
   purgeable space of its own answers that question with nothing, or with
   zero, and falls back to the plain free space it does report: HFS+ and exFAT
   drives are a first-class destination for an app that exists to make room.

   `nil` is an ordinary answer rather than a failure: neither figure is
   available on volumes that don't report capacity at all, which includes SMB
   and NFS mounts. Every caller has to carry on without it.
   */
  public var availableCapacityForImportantUsage: Int? {
    purgeableAwareCapacity ?? freeCapacity
  }

  /**
   Room including whatever the system would purge to make it, which only APFS
   volumes account for. Others withhold the value or report it as zero, and
   zero read as an answer would refuse every run on the volume.
   */
  private var purgeableAwareCapacity: Int? {
    let capacity = try? resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
    guard let capacity, capacity > 0 else { return nil }
    return Int(capacity)
  }

  /// The free space a volume reports without accounting for anything purgeable.
  private var freeCapacity: Int? {
    try? resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
  }
}
