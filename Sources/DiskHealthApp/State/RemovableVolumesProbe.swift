import Foundation

/// Lists each mounted volume once so macOS shows the “Removable Volumes” permission prompt
/// (`NSRemovableVolumesUsageDescription`) and grants access before any read or performance test.
/// Only local volumes other than the boot volume are touched: a network share that stopped
/// answering would otherwise block the caller, and the boot volume needs no permission.
enum RemovableVolumesProbe {
    static let volumesDirectory = URL(fileURLWithPath: "/Volumes")

    /// True for a local volume that is not the root file system (by resource keys, not by name).
    nonisolated static func shouldTouch(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRootFileSystemKey, .isDirectoryKey]),
              values.isDirectory == true else { return false }
        return values.volumeIsLocal == true && values.volumeIsRootFileSystem != true
    }

    nonisolated static func volumesToTouch(in directory: URL = volumesDirectory) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.volumeIsLocalKey, .volumeIsRootFileSystemKey, .isDirectoryKey])) ?? []
        return entries.filter(shouldTouch)
    }

    /// Blocking: call it off the main thread.
    nonisolated static func touch(in directory: URL = volumesDirectory) {
        for volume in volumesToTouch(in: directory) {
            _ = try? FileManager.default.contentsOfDirectory(atPath: volume.path)
        }
    }
}
