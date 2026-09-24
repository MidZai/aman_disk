import Testing
import Foundation
@testable import DiskHealthApp

/// Tout se passe dans un dossier temporaire : l'ancienne version de ce test supprimait le vrai
/// dossier `Application Support/io.github.aman-disk.AmanDisk` de la machine.
@Suite struct MigrationServiceTests {
    @Test func oldFoldersAreCopiedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "aman.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let oldHistory = root.appendingPathComponent("io.github.aman-disk.DiskHealth/History")
        try FileManager.default.createDirectory(at: oldHistory, withIntermediateDirectories: true)
        try "dummy".write(to: oldHistory.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

        MigrationService.migrateIfNeeded(appSupport: root, defaults: defaults)

        let copied = root.appendingPathComponent("\(AppInfo.bundleIdentifier)/History/test.txt")
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(defaults.bool(forKey: "migratedFromDiskHealth"))
        // Copie et non déplacement.
        #expect(FileManager.default.fileExists(atPath: oldHistory.appendingPathComponent("test.txt").path))
    }

    @Test func foreignPreferencesAreRemovedButOwnKeysKept() throws {
        let suite = "aman.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.setPersistentDomain([
            "com.apple.trackpad.scrollBehavior": 2,
            "AKLastLocale": "fr_DZ",
            PreferenceKey.alertsEnabled: true,
            "NSWindow Frame main": "0 0 100 100"
        ], forName: suite)

        MigrationService.removeForeignPreferences(defaults: defaults, domain: suite)

        let kept = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(kept["com.apple.trackpad.scrollBehavior"] == nil)
        #expect(kept["AKLastLocale"] == nil)
        #expect(kept[PreferenceKey.alertsEnabled] as? Bool == true)
        #expect(kept["NSWindow Frame main"] != nil)
    }
}
