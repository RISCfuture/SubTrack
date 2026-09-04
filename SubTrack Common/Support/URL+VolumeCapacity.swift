public import Foundation

extension URL {
  /**
   How many bytes this URL's volume can give to something the user is waiting
   on, or `nil` when the volume won't say.

   The system counts space it would purge to satisfy the request, so this is
   larger than the free space Finder reports and is the number a preflight
   should compare against — asking for the raw free space would refuse writes
   that would in fact have succeeded.

   `nil` is an ordinary answer rather than a failure: the key is unavailable on
   volumes that don't report capacity at all, which includes SMB and NFS
   mounts. Every caller has to carry on without it.
   */
  public var availableCapacityForImportantUsage: Int? {
    let capacity = try? resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
    return capacity.map(Int.init)
  }
}
