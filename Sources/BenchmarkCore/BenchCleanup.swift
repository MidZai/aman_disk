import Foundation
import DiskHealthCore

public enum BenchCleanup {
    /// A test file modified more recently than this may belong to another running instance
    /// (`diskprobe`, or a second copy launched when the language changes): it is left alone.
    public static let minimumAge: TimeInterval = 2 * 60

    public static func run(volumes: [Volume], bundleIdentifier: String = "io.github.aman-disk.AmanDisk", now: Date = Date()) {
        let fileManager = FileManager.default
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        
        var baseURLs: [URL] = []
        baseURLs.append(cachesURL.appendingPathComponent(bundleIdentifier).appendingPathComponent("DiskHealthBench.noindex"))
        
        for volume in volumes {
            let url = URL(fileURLWithPath: volume.mountPoint)
            if url.path != "/" && url.path != "/System/Volumes/Data" {
                baseURLs.append(url.appendingPathComponent("DiskHealthBench.noindex"))
            }
        }
        
        for baseURL in baseURLs {
            guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent.hasPrefix("DiskHealthBench-") && fileURL.lastPathComponent.hasSuffix(".tmp") else { continue }
                if let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modified) < minimumAge {
                    continue
                }
                try? fileManager.removeItem(at: fileURL)
            }
            removeTestFolderIfEmpty(baseURL)
        }
    }

    public static let testFolderName = "DiskHealthBench.noindex"

    /// Removes a `DiskHealthBench.noindex` folder once nothing is left in it (success, error or cancellation).
    public static func removeTestFolderIfEmpty(_ folder: URL) {
        guard folder.lastPathComponent == testFolderName,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
