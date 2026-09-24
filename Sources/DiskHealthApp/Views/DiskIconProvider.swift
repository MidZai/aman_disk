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

    /// Icône Finder du volume, mise en cache : `NSWorkspace.icon(forFile:)` interroge le système
    /// de fichiers, et la barre latérale est redessinée à chaque relevé (toutes les 30 s).
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
