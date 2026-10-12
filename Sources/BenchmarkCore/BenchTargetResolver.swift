import Foundation
import DiskHealthCore

public enum TargetRejectionReason: Equatable, CustomStringConvertible {
    case unmounted
    case readOnly
    case network
    case diskImage
    case timeMachine
    case accessDenied
    case insufficientFreeSpace(FreeSpaceVerdict)
    
    public var description: String {
        switch self {
        case .unmounted: return L("Unmounted", "Non monté")
        case .readOnly: return L("Read-only", "Lecture seule")
        case .network: return L("Network", "Réseau")
        case .diskImage: return L("Disk image", "Image disque")
        case .timeMachine: return "Time Machine"
        case .accessDenied: return L("Access denied", "Accès refusé")
        case .insufficientFreeSpace(_): return L("Not enough space", "Espace insuffisant")
        }
    }
}

public struct BenchTarget: Identifiable {
    public var label: String {
        if let r = rejectionReason {
            return "\(volume.name) (\(r.description))"
        }
        return volume.name
    }
    public var id: String { volume.id }
    public let volume: Volume
    public let testDirectoryURL: URL
    public let rejectionReason: TargetRejectionReason?
    public let availableBytes: UInt64
    public let isEncrypted: Bool
    public let fileSystem: String
}

public enum BenchTargetResolver {
    /// True when `directory`, or the nearest ancestor that exists, is writable. Writes nothing.
    static func canWrite(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        var url = directory.standardizedFileURL
        while !fileManager.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return false }
            url = parent
        }
        return fileManager.isWritableFile(atPath: url.path)
    }

    public static func resolveTargets(volumes: [Volume], disks: [PhysicalDisk], bundleIdentifier: String = "io.github.aman-disk.AmanDisk", fileSize: UInt64 = 1073741824) -> [BenchTarget] {
        var targets: [BenchTarget] = []
        
        let fileManager = FileManager.default
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        
        for volume in volumes {
            if volume.mountPoint.isEmpty || !fileManager.fileExists(atPath: volume.mountPoint) {
                targets.append(BenchTarget(
                    volume: volume,
                    testDirectoryURL: URL(fileURLWithPath: "/"),
                    rejectionReason: .unmounted,
                    availableBytes: 0,
                    isEncrypted: false,
                    fileSystem: volume.format
                ))
                continue
            }
            
            let url = URL(fileURLWithPath: volume.mountPoint)
            guard let resourceValues = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeAvailableCapacityKey, .volumeIsEncryptedKey, .volumeLocalizedFormatDescriptionKey]) else {
                targets.append(BenchTarget(
                    volume: volume,
                    testDirectoryURL: URL(fileURLWithPath: "/"),
                    rejectionReason: .unmounted,
                    availableBytes: 0,
                    isEncrypted: false,
                    fileSystem: volume.format
                ))
                continue
            }
            
            let isReadOnly = resourceValues.volumeIsReadOnly == true
            let isLocal = resourceValues.volumeIsLocal == true
            let available = UInt64(resourceValues.volumeAvailableCapacity ?? 0)
            let isEncrypted = resourceValues.volumeIsEncrypted == true
            let fileSystem = resourceValues.volumeLocalizedFormatDescription ?? "Unknown"
            
            var reason: TargetRejectionReason? = nil
            
            // Look up the underlying physical disk to see if it's a disk image
            var isDiskImage = false
            for bsd in volume.physicalDiskBSDNames {
                if let pd = disks.first(where: { $0.bsdName == bsd }), pd.protocolType == .virtualDisk {
                    isDiskImage = true
                }
            }
            
            if !isLocal {
                reason = .network
            } else if isDiskImage || volume.format.contains("Disk Image") {
                reason = .diskImage
            } else if volume.name.lowercased().contains("time machine") || url.path.contains("TimeMachine") {
                reason = .timeMachine
            } else if isReadOnly && url.path != "/" && url.path != "/System/Volumes/Data" {
                reason = .readOnly
            } else {
                let spaceCheck = BenchMath.checkFreeSpace(fileSize: fileSize, available: available)
                if spaceCheck != .ok {
                    reason = .insufficientFreeSpace(spaceCheck)
                }
            }
            
            var testDirURL: URL
            if url.path == "/" || url.path == "/System/Volumes/Data" {
                testDirURL = cachesURL.appendingPathComponent(bundleIdentifier).appendingPathComponent("DiskHealthBench.noindex")
                if isReadOnly && reason == .readOnly {
                    reason = nil // It's system volume, we use caches dir which is writable
                }
            } else {
                testDirURL = url.appendingPathComponent("DiskHealthBench.noindex")
            }
            
            if reason == nil && !canWrite(at: testDirURL) {
                // Nothing is written on the volume until the user starts a test: the check only
                // asks the file system whether the test folder (or its nearest existing parent)
                // accepts writes.
                reason = .accessDenied
            }
            
            targets.append(BenchTarget(
                volume: volume,
                testDirectoryURL: testDirURL,
                rejectionReason: reason,
                availableBytes: available,
                isEncrypted: isEncrypted,
                fileSystem: fileSystem
            ))
        }
        return targets
    }
}
