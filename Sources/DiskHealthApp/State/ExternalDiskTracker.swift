import Foundation
import DiskHealthCore

/// Remembers external drives after they are unplugged, with the date they were last seen, so the
/// app can keep showing them. Pure: no timer, no I/O; `AppManager` feeds it each new list.
struct ExternalDiskTracker {
    private var history: [String: (disk: RealDisk, lastSeen: Date)] = [:]

    /// Records the external drives that left between `previous` and `current` (only when
    /// `recordDepartures`: the first list and background re-reads don't count as unplugging),
    /// forgets the ones that came back, and returns those still disconnected, most recent first.
    mutating func update(previous: [RealDisk], current: [RealDisk], recordDepartures: Bool, now: Date = Date()) -> [DisconnectedDisk] {
        if recordDepartures {
            let currentIds = Set(current.map(\.id))
            for disk in previous where disk.physical.isExternal && !currentIds.contains(disk.id) {
                history[disk.benchmarkKey] = (disk, now)
            }
        }
        for disk in current where disk.physical.isExternal {
            history.removeValue(forKey: disk.benchmarkKey)
        }
        let connectedKeys = Set(current.map(\.benchmarkKey))
        return history.values
            .filter { !connectedKeys.contains($0.disk.benchmarkKey) }
            .map { DisconnectedDisk(disk: $0.disk, lastSeen: $0.lastSeen) }
            .sorted { $0.lastSeen > $1.lastSeen }
    }
}
