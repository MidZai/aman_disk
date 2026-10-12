import Foundation
import DiskHealthCore

/// NVMe Identify data reused between reads (it doesn't change for a given drive), keyed by BSD name.
/// A BSD name is reused by whatever drive is plugged next: a plug/unplug event for that name, or a
/// wake from sleep (drives may have been swapped), drops the cached entry so it is read again.
struct IdentifyCache {
    private var staleNames: Set<String> = []
    private var allStale = false

    mutating func invalidate(bsdName: String) {
        staleNames.insert(bsdName)
    }

    mutating func invalidateAll() {
        allStale = true
    }

    /// Identify data worth reusing for the next read, by BSD name. Invalidations are consumed:
    /// a dropped entry is read from the drive again and then cached as usual.
    mutating func known(from disks: [RealDisk]) -> [String: NVMeIdentify] {
        defer { staleNames = []; allStale = false }
        if allStale { return [:] }
        var result: [String: NVMeIdentify] = [:]
        for disk in disks where !staleNames.contains(disk.id) {
            if let id = disk.identify { result[disk.id] = id }
        }
        return result
    }
}
