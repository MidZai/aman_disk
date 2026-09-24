import Foundation
import DiskHealthCore

public enum MigrationService {
    static let historyMergedKey = "historyMergedIntoAmanFolder"
    static let foreignPreferencesRemovedKey = "foreignPreferencesRemoved"

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

    /// Copie les dossiers des anciennes versions (« DiskHealth ») vers le dossier actuel, une seule fois.
    public static func migrateIfNeeded(appSupport: URL? = nil, defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: "migratedFromDiskHealth") { return }
        let fm = FileManager.default
        guard let appSupport = appSupport ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let newDir = appSupport.appendingPathComponent(AppInfo.bundleIdentifier)

        for oldDirName in ["com.example.diskhealth", "io.github.aman-disk.DiskHealth", "io.github.aman-disk.DiskHealthApp", "DiskHealth"] {
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

    /// Clés que l'app écrit elle-même ; les autres ont été recopiées par erreur.
    static let ownKeys: Set<String> = [
        PreferenceKey.stayInMenuBar, PreferenceKey.showMenuBarTemperature, PreferenceKey.dockShowsHealth,
        PreferenceKey.alertsEnabled, PreferenceKey.language, "alertStates", historyMergedKey, foreignPreferencesRemovedKey, "migratedFromDiskHealth"
    ]

    /// La migration 0.9 recopiait `dictionaryRepresentation()`, qui contient aussi les réglages globaux
    /// du Mac (trackpad, clavier, langue…). Ces copies figées masquaient les vrais réglages pour l'app.
    /// On ne garde que nos clés et celles d'AppKit (cadres de fenêtres, panneaux…).
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
