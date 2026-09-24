import Foundation
import DiskHealthCore

public enum MigrationService {
    static let historyMergedKey = "historyMergedIntoAmanFolder"
    static let foreignPreferencesRemovedKey = "foreignPreferencesRemoved"

    /// Up to 0.9, the history was still written to `Application Support/DiskHealth/History`,
    /// even after the initial migration. Merges these readings into the current folder, once
    /// (a copy: the old folder isn't changed).
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

    /// Copies the folders of older versions (“DiskHealth”) to the current folder, once.
    public static func migrateIfNeeded(appSupport: URL? = nil, defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: "migratedFromDiskHealth") { return }
        let fm = FileManager.default
        guard let appSupport = appSupport ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let newDir = appSupport.appendingPathComponent(AppInfo.bundleIdentifier)

        for oldDirName in ["com.example.diskhealth", "DiskHealth"] {
            let oldDir = appSupport.appendingPathComponent(oldDirName)
            guard fm.fileExists(atPath: oldDir.path) else { continue }
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            for item in ["History", "benchmarks"] {
                let from = oldDir.appendingPathComponent(item)
                let to = newDir.appendingPathComponent(item)
                if fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
                    try? fm.copyItem(at: from, to: to)
                }
            }
        }
        defaults.set(true, forKey: "migratedFromDiskHealth")
    }

    /// Keys the app writes itself; the others were copied by mistake.
    static let ownKeys: Set<String> = [
        PreferenceKey.stayInMenuBar, PreferenceKey.showMenuBarTemperature, PreferenceKey.dockShowsHealth,
        PreferenceKey.alertsEnabled, PreferenceKey.language, "alertStates", historyMergedKey, foreignPreferencesRemovedKey, "migratedFromDiskHealth"
    ]

    /// The 0.9 migration copied `dictionaryRepresentation()`, which also contains the Mac's global
    /// settings (trackpad, keyboard, language…). These frozen copies hid the real settings from the app.
    /// Only our own keys and AppKit's (window frames, panels…) are kept.
    public static func removeForeignPreferences(defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) {
        guard let domain, !defaults.bool(forKey: foreignPreferencesRemovedKey),
              var persisted = defaults.persistentDomain(forName: domain) else { return }
        for key in persisted.keys where !ownKeys.contains(key) && !key.hasPrefix("NS") {
            persisted.removeValue(forKey: key)
        }
        persisted[foreignPreferencesRemovedKey] = true
        defaults.setPersistentDomain(persisted, forName: domain)
    }
}
