import AppKit
import SwiftUI
import DiskHealthCore

public enum DiskIconProvider {
    public static func icon(for physical: PhysicalDisk) -> some View {
        let name = physical.isInternal ? "internaldrive" : "externaldrive"
        return Image(systemName: name)
            .foregroundStyle(.secondary)
            .fontWeight(.light)
    }
    
    public static func icon(for disk: RealDisk) -> some View {
        return icon(for: disk.physical)
    }
    
    public static func icon(for volume: Volume) -> some View {
        let nsIcon = NSWorkspace.shared.icon(forFile: volume.mountPoint)
        return Image(nsImage: nsIcon)
            .resizable()
            .scaledToFit()
    }
}
