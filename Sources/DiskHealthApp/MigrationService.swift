import Foundation

public enum MigrationService {
    public static func migrateIfNeeded() {
        let userDefaults = UserDefaults.standard
        if userDefaults.bool(forKey: "migratedFromDiskHealth") { return }
        
        // Migrate defaults
        let oldDefaults = UserDefaults(suiteName: "com.example.diskhealth") ?? UserDefaults(suiteName: "io.github.aman-disk.DiskHealth")
        if let dict = oldDefaults?.dictionaryRepresentation() {
            for (key, value) in dict {
                if !key.starts(with: "Apple") && !key.starts(with: "NS") {
                    userDefaults.set(value, forKey: key)
                }
            }
        }
        
        // Migrate files
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let newDir = appSupport.appendingPathComponent("io.github.aman-disk.AmanDisk")
        
        let oldDirs = ["com.example.diskhealth", "io.github.aman-disk.DiskHealth", "io.github.aman-disk.DiskHealthApp", "DiskHealth"]
        
        for oldDirName in oldDirs {
            let oldDir = appSupport.appendingPathComponent(oldDirName)
            if fm.fileExists(atPath: oldDir.path) {
                try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
                
                // Copy History (Temperature)
                let oldHistory = oldDir.appendingPathComponent("History")
                let newHistory = newDir.appendingPathComponent("History")
                if fm.fileExists(atPath: oldHistory.path) && !fm.fileExists(atPath: newHistory.path) {
                    try? fm.copyItem(at: oldHistory, to: newHistory)
                }
                
                // Copy Benchmarks
                let oldBench = oldDir.appendingPathComponent("benchmarks")
                let newBench = newDir.appendingPathComponent("benchmarks")
                if fm.fileExists(atPath: oldBench.path) && !fm.fileExists(atPath: newBench.path) {
                    try? fm.copyItem(at: oldBench, to: newBench)
                }
                
                // Copy bench-inflight.json
                let oldInflight = oldDir.appendingPathComponent("bench-inflight.json")
                let newInflight = newDir.appendingPathComponent("bench-inflight.json")
                if fm.fileExists(atPath: oldInflight.path) && !fm.fileExists(atPath: newInflight.path) {
                    try? fm.copyItem(at: oldInflight, to: newInflight)
                }
            }
        }
        
        userDefaults.set(true, forKey: "migratedFromDiskHealth")
        userDefaults.synchronize()
    }
}
