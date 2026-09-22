import AppKit
import SwiftUI
import DiskHealthCore

public enum DiskIconProvider {
    public static func icon(for disk: RealDisk) -> Image {
        if !disk.physical.volumeNames.isEmpty {
            // Find volume mount point
            let volumes = VolumeDiscovery.listVolumes()
            if let vol = volumes.first(where: { $0.physicalDiskBSDName == disk.physical.bsdName }) {
                let nsIcon = NSWorkspace.shared.icon(forFile: vol.mountPoint)
                return Image(nsImage: nsIcon)
            }
        }
        
        let name = disk.physical.isInternal ? "internaldrive.fill" : "externaldrive.fill"
        return Image(systemName: name)
    }
    
    public static func icon(for volume: Volume) -> Image {
        let nsIcon = NSWorkspace.shared.icon(forFile: volume.mountPoint)
        return Image(nsImage: nsIcon)
    }
}
