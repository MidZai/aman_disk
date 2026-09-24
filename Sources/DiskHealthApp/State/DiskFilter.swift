import Foundation
import DiskHealthCore

/// Disques affichés par l'app (0.9 : disques internes seulement).
enum DiskFilter {
    /// Disque surveillé : interne, ni USB, ni virtuel, ni image disque.
    static func isMonitored(_ disk: PhysicalDisk) -> Bool {
        disk.isInternal && disk.connection != .usb && !disk.isVirtual && !disk.isDiskImage
            && disk.protocolType != .virtualDisk
    }

    static func filter(disks: [RealDisk], volumes: [Volume]) -> (disks: [RealDisk], volumes: [Volume]) {
        let filteredDisks = disks.filter { isMonitored($0.physical) }
        let names = Set(filteredDisks.map(\.physical.bsdName))
        // Rattachement par disque physique (et non par nom de volume, qui peut être en double).
        let filteredVols = volumes.filter { v in v.physicalDiskBSDNames.contains(where: names.contains) }
        return (filteredDisks, filteredVols)
    }
}
