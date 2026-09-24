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
            // « / » (système) et « /System/Volumes/Data » (données) partagent le même conteneur APFS
            // et le même espace : comme le Finder, on n'affiche que « Macintosh HD ».
            if path != "/" && !path.hasPrefix("/Volumes/") {
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
            var physicalDiskBSDNames: [String] = []
            
            if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) {
                if let bsd = DADiskGetBSDName(disk) {
                    bsdName = String(cString: bsd)
                    physicalDiskBSDNames = getPhysicalDiskBSDNames(for: bsdName)
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
                physicalDiskBSDNames: physicalDiskBSDNames
            ))
        }
        
        return volumes
    }
    
    public static func getPhysicalDiskBSDNames(for volumeBSDName: String) -> [String] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, volumeBSDName))
        guard service != 0 else { return [] }
        let node = IOKitRegistryNode(entry: service, shouldRelease: true)
        return PhysicalDiskResolver.resolvePhysicalDisks(from: node)
    }
}
