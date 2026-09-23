import Foundation
import DiskHealthCore

public enum MigrationService {
    static let historyMergedKey = "historyMergedIntoAmanFolder"
    
    /// Jusqu'à la 0.9, l'historique était encore écrit dans `Application Support/DiskHealth/History`,
    /// même après la migration initiale. Fusionne une seule fois ces mesures dans le dossier actuel
    /// (copie : l'ancien dossier n'est pas modifié).
    public static func mergeLegacyHistoryIfNeeded(appSupport: URL? = nil, store: HistoryStore = .shared, defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: historyMergedKey) { return }
        let fm = FileManager.default
        guard let base = appSupport ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = base.appendingPathComponent("DiskHealth").appendingPathComponent("History")
        let files = (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            store.importSamples(from: file, for: file.deletingPathExtension().lastPathComponent)
        }
        defaults.set(true, forKey: historyMergedKey)
    }

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
