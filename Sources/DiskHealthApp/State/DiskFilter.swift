import Foundation
import DiskHealthCore

/// Drives shown by the app (internal and external physical drives).
enum DiskFilter {
    /// Monitored drive: physical drive (internal or external), not virtual, not a disk image, not RAM disk.
    static func isMonitored(_ disk: PhysicalDisk) -> Bool {
        if disk.isVirtual || disk.isDiskImage || disk.protocolType == .virtualDisk {
            return false
        }
        if case .other(let name) = disk.driveConnection {
            let lower = name.lowercased()
            if lower.contains("file") || lower.contains("virtual") || lower.contains("ram") || lower.contains("network") {
                return false
            }
        }
        return true
    }

    static func filter(disks: [RealDisk], volumes: [Volume]) -> (disks: [RealDisk], volumes: [Volume]) {
        let filteredDisks = disks.filter { isMonitored($0.physical) }
        let names = Set(filteredDisks.map(\.physical.bsdName))
        // Matched by physical disk (not by volume name, which can be duplicated).
        let filteredVols = volumes.filter { v in v.physicalDiskBSDNames.contains(where: names.contains) }
        return (filteredDisks, filteredVols)
    }
}
