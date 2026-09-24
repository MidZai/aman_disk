import AppKit
import SwiftUI
import DiskHealthCore

enum DiskIconProvider {
    static func icon(for physical: PhysicalDisk) -> some View {
        Image(systemName: physical.isInternal ? "internaldrive" : "externaldrive")
            .foregroundStyle(.secondary)
            .fontWeight(.light)
    }

    static func icon(for disk: RealDisk) -> some View {
        icon(for: disk.physical)
    }

    /// Finder icon of the volume, cached: `NSWorkspace.icon(forFile:)` queries the file
    /// system, and the sidebar is redrawn on every reading (every 30 s).
    @MainActor
    static func icon(for volume: Volume) -> some View {
        Image(nsImage: cachedIcon(path: volume.mountPoint))
            .resizable()
            .scaledToFit()
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    private static func cachedIcon(path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
