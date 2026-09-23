import Foundation
import DiskHealthCore

public enum DiskFilter {
    public static func filter(disks: [RealDisk], volumes: [Volume]) -> (disks: [RealDisk], volumes: [Volume]) {
        let filteredDisks = disks.filter { 
            $0.physical.isInternal && 
            $0.physical.connection != .usb &&
            !$0.physical.isVirtual && 
            !$0.physical.isDiskImage
        }
        let filteredVols = volumes.filter { v in
            filteredDisks.contains { d in d.physical.volumeNames.contains(v.name) }
        }
        return (filteredDisks, filteredVols)
    }
}
