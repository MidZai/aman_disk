import Foundation
import DiskHealthCore

public enum BenchCleanup {
    public static func run(volumes: [Volume], bundleIdentifier: String = "io.github.aman-disk.AmanDisk") {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        
        var baseURLs: [URL] = []
        baseURLs.append(cachesURL.appendingPathComponent(bundleIdentifier).appendingPathComponent("DiskHealthBench.noindex"))
        
        for volume in volumes {
            let url = URL(fileURLWithPath: volume.mountPoint)
            if url.path != "/" && url.path != "/System/Volumes/Data" {
                baseURLs.append(url.appendingPathComponent("DiskHealthBench.noindex"))
            }
        }
        
        for baseURL in baseURLs {
            guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.hasPrefix("DiskHealthBench-") && fileURL.lastPathComponent.hasSuffix(".tmp") {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
}
