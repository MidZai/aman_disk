import Testing
import Foundation
@testable import DiskHealthCore
@testable import BenchmarkCore

@Suite struct ExternalHistoryPrivacyTests {

    @Test func testDiskIdentityHashStabilityAndPrivacy() {
        let model = "Samsung T7 Portable"
        let serial = "S42VNF0M123456"

        let key1 = DiskIdentity.key(model: model, serial: serial)
        let key2 = DiskIdentity.key(model: model, serial: serial)

        // Deterministic on reconnection
        #expect(key1 == key2)
        #expect(key1.count == 16)
        #expect(!key1.isEmpty)

        // Privacy: Raw serial and model never appear in the hash
        #expect(!key1.contains(serial))
        #expect(!key1.contains(model))

        // Different serial produces different hash
        let key3 = DiskIdentity.key(model: model, serial: "S42VNF0M999999")
        #expect(key1 != key3)
    }

    @Test func testApplicationSupportFilesContainNoPlaintextSerial() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("aman_privacy_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretSerial = "TOP_SECRET_SERIAL_987654321"
        let model = "SanDisk Extreme Pro"

        let historyStore = HistoryStore(baseURL: tempDir)
        let eventLog = DiskEventLog(baseURL: tempDir)

        let key = DiskIdentity.key(model: model, serial: secretSerial)

        // Record a history sample
        let sample = HistorySample(
            date: Date(),
            temperatureC: 38,
            percentageUsed: 5,
            dataUnitsWritten: 1_000_000,
            dataUnitsRead: 2_000_000,
            powerOnHours: 120,
            mediaErrors: 0,
            availableSpare: 100
        )
        historyStore.record(sample, for: key)
        _ = historyStore.samples(for: key, since: .distantPast)

        // Record an event
        eventLog.append(DiskEvent(kind: .smartEnabled), for: key)

        // Record a benchmark result
        let benchDir = tempDir.appendingPathComponent("benchmarks")
        try FileManager.default.createDirectory(at: benchDir, withIntermediateDirectories: true)
        let benchResult = BenchmarkResult(
            id: UUID(),
            date: Date(),
            appVersion: "0.9.8",
            diskKey: key,
            profile: .quick,
            fileSize: 1_048_576,
            conditions: BenchConditions(
                volumeName: "FastExternal",
                fileSystem: "APFS",
                encrypted: false,
                onBattery: false,
                lowPowerMode: false,
                thermalStateStart: "nominal",
                temperatureStartC: 35,
                temperatureMaxC: 38,
                bytesWritten: 1_048_576
            ),
            tests: [],
            completed: true,
            stopReason: nil
        )
        let benchData = try JSONEncoder().encode([benchResult])
        try benchData.write(to: benchDir.appendingPathComponent("\(key).json"))

        // Recursively inspect ALL files in tempDir
        guard let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) else {
            Issue.record("Failed to enumerate directory")
            return
        }

        var filesInspected = 0
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                filesInspected += 1
                // Check filename
                #expect(!fileURL.lastPathComponent.contains(secretSerial))

                // Check file content
                let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                #expect(!content.contains(secretSerial))
            }
        }

        #expect(filesInspected >= 3)
    }

    @Test func testReconnectionRestoresHistoryViaFingerprintKey() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("aman_reconnect_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = "OWC Envoy Pro FX"
        let serial = "OWC-TB-99128"
        let key = DiskIdentity.key(model: model, serial: serial)

        let store = HistoryStore(baseURL: tempDir)

        // 1. Initial connection: record samples
        let sample1 = HistorySample(date: Date().addingTimeInterval(-60), temperatureC: 34, percentageUsed: 2, dataUnitsWritten: 500, dataUnitsRead: 1000, powerOnHours: 10, mediaErrors: 0, availableSpare: 100)
        let sample2 = HistorySample(date: Date(), temperatureC: 36, percentageUsed: 2, dataUnitsWritten: 600, dataUnitsRead: 1200, powerOnHours: 10, mediaErrors: 0, availableSpare: 100)
        store.record(sample1, for: key)
        store.record(sample2, for: key)
        _ = store.samples(for: key, since: .distantPast)

        // 2. Simulate disconnection: drive unplugged, new store instance created
        let newStore = HistoryStore(baseURL: tempDir)

        // 3. Reconnection: drive plugged back in, key re-derived from model + serial
        let reconnectedKey = DiskIdentity.key(model: model, serial: serial)
        #expect(reconnectedKey == key)

        let retrievedSamples = newStore.samples(for: reconnectedKey, since: .distantPast)
        #expect(retrievedSamples.count == 2)
        #expect(retrievedSamples.first?.temperatureC == 34)
        #expect(retrievedSamples.last?.temperatureC == 36)
    }
}
