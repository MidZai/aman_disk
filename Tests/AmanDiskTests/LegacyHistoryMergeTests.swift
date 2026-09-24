import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Readings written to the old `DiskHealth/History` folder are merged once.
@Suite struct LegacyHistoryMergeTests {
    @Test func legacyHistoryIsMergedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "aman.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        
        let legacyDir = root.appendingPathComponent("DiskHealth/History")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let old = [HistorySample(date: Date(timeIntervalSince1970: 1_000), temperatureC: 33, percentageUsed: nil, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil)]
        try JSONEncoder().encode(old).write(to: legacyDir.appendingPathComponent("KEY.json"))
        
        let store = HistoryStore(baseURL: root.appendingPathComponent("new"))
        store.record(HistorySample(date: Date(timeIntervalSince1970: 2_000), temperatureC: 35, percentageUsed: nil, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil), for: "KEY")
        
        MigrationService.mergeLegacyHistoryIfNeeded(appSupport: root, store: store, defaults: defaults)
        #expect(store.samples(for: "KEY", since: .distantPast).map(\.temperatureC) == [33, 35])
        #expect(defaults.bool(forKey: MigrationService.historyMergedKey))
        // The old file is copied, not moved.
        #expect(FileManager.default.fileExists(atPath: legacyDir.appendingPathComponent("KEY.json").path))
        
        // Second call: no effect.
        MigrationService.mergeLegacyHistoryIfNeeded(appSupport: root, store: store, defaults: defaults)
        #expect(store.samples(for: "KEY", since: .distantPast).count == 2)
    }
}
