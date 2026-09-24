import Foundation
import DiskHealthCore

/// Drives shown by the app (0.9: internal drives only).
enum DiskFilter {
    /// Monitored drive: internal, not USB, not virtual, not a disk image.
    static func isMonitored(_ disk: PhysicalDisk) -> Bool {
        disk.isInternal && disk.connection != .usb && !disk.isVirtual && !disk.isDiskImage
            && disk.protocolType != .virtualDisk
    }

    static func filter(disks: [RealDisk], volumes: [Volume]) -> (disks: [RealDisk], volumes: [Volume]) {
        let filteredDisks = disks.filter { isMonitored($0.physical) }
        let names = Set(filteredDisks.map(\.physical.bsdName))
        // Matched by physical disk (not by volume name, which can be duplicated).
        let filteredVols = volumes.filter { v in v.physicalDiskBSDNames.contains(where: names.contains) }
        return (filteredDisks, filteredVols)
    }
}
