import Foundation
import IOKit
import DiskArbitration

public enum VolumeDiscovery {
    public static func listVolumes() -> [Volume] {
        var volumes: [Volume] = []
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsLocalKey
        ]
        
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) else {
            return []
        }
        
        for url in urls {
            let path = url.path
            if path != "/" && path != "/System/Volumes/Data" && !path.hasPrefix("/Volumes/") {
                continue
            }
            
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true else {
                continue
            }
            
            let name = values.volumeName ?? url.lastPathComponent
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let format = values.volumeLocalizedFormatDescription ?? "Unknown"
            
            var bsdName = ""
            var physicalDiskBSDName: String? = nil
            
            if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) {
                if let bsd = DADiskGetBSDName(disk) {
                    bsdName = String(cString: bsd)
                    physicalDiskBSDName = getPhysicalDiskBSDName(for: bsdName)
                }
            }
            
            if bsdName.isEmpty { continue }
            
            volumes.append(Volume(
                bsdName: bsdName,
                name: name,
                mountPoint: path,
                format: format,
                totalBytes: total,
                availableBytes: available,
                physicalDiskBSDName: physicalDiskBSDName
            ))
        }
        
        return volumes
    }
    
    private static func getPhysicalDiskBSDName(for volumeBSDName: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, volumeBSDName))
        if service == 0 { return nil }
        
        var current = service
        var physicalName: String? = nil
        
        while current != 0 {
            if let whole = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "Whole" as CFString, kCFAllocatorDefault, 0) as? Bool, whole == true {
                if !isSynthetic(service: current) {
                    if let bsd = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault, 0) as? String {
                        physicalName = bsd
                        IOObjectRelease(current)
                        break
                    }
                }
            }
            
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }
        return physicalName
    }
    
    private static func isSynthetic(service: io_object_t) -> Bool {
        var current = service
        IOObjectRetain(current)
        
        var hasBlockStorage = false
        var isAPFSContainer = false
        
        while current != 0 {
            if IOObjectConformsTo(current, "AppleAPFSContainerScheme") != 0 {
                isAPFSContainer = true
            }
            if IOObjectConformsTo(current, "IOBlockStorageDevice") != 0 {
                hasBlockStorage = true
            }
            
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }
        return isAPFSContainer || !hasBlockStorage
    }
}
