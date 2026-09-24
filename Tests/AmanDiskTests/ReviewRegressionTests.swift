import Testing
import Foundation
@testable import DiskHealthApp
@testable import DiskHealthCore
@testable import BenchmarkCore

/// Regression tests for the defects fixed during the 0.9.1 review.
@Suite struct ReviewRegressionTests {
    init() { Localization.language = .english }

    // MARK: Test data

    static func nvmeLog(percentageUsed: UInt8 = 2, temperatureK: UInt16 = 309, mediaErrors: UInt64 = 0,
                        written: UInt64 = 215_208_576) -> NVMeSmartLog {
        NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: temperatureK, availableSpare: 100,
                     availableSpareThreshold: 99, percentageUsed: percentageUsed, dataUnitsRead: 201_721_690,
                     dataUnitsWritten: written, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0,
                     powerCycles: 242, powerOnHours: 3440, unsafeShutdowns: 54, mediaErrors: mediaErrors, errorLogEntries: 0)
    }

    static let identify = NVMeIdentify(serialNumber: "C02SECRET1234", modelNumber: "APPLE SSD AP0512N", firmwareRevision: "1310",
                                       warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 500_277_790_720)

    static func ataAttribute(_ id: UInt8, current: UInt8 = 100, worst: UInt8 = 100, threshold: UInt8 = 0, raw: UInt64) -> ATASmartAttribute {
        let bytes = (0..<6).map { UInt8((raw >> ($0 * 8)) & 0xFF) }
        return ATASmartAttribute(id: id, flags: 0, current: current, worst: worst, threshold: threshold, raw: bytes, rawValue: raw)
    }

    static func ataSnapshot(_ attributes: [ATASmartAttribute], model: String = "APPLE SSD SM0512G") -> ATASmartSnapshot {
        ATASmartSnapshot(attributes: attributes, model: model, firmware: "BXW1PA0Q", serialNumber: "EXAMPLE0003891",
                         rotationRate: 1, thresholdExceeded: false, checksumValid: true)
    }

    static func physical(_ proto: StorageProtocol) -> PhysicalDisk {
        PhysicalDisk(bsdName: "disk0", model: "APPLE SSD", sizeBytes: 500_000_000_000, isInternal: true,
                     connection: proto == .nvme ? .nvmeInternal : .other, volumeNames: ["Macintosh HD"],
                     protocolType: proto, mediumType: .solidState, healthCapability: .supported)
    }

    // MARK: Report privacy

    @Test @MainActor func serialIsMaskedInATAReports() throws {
        let snapshot = DiskHealthSnapshot.ata(Self.ataSnapshot([Self.ataAttribute(0xC2, raw: 40)]))
        let disk = RealDisk(physical: Self.physical(.pcieAhci), snapshot: snapshot, health: AppManager.evaluate(snapshot))
        let report = ReportData(disk: disk, options: ExportOptions(includeSerial: false, includeHistory: false),
                                benchmark: nil, history: .empty, generatedAt: Date())

        let text = ExportService.reportText(report)
        #expect(!text.contains("EXAMPLE0003891"))
        #expect(text.contains("Hidden"))
        let json = try #require(String(data: try ExportService.reportJSON(report), encoding: .utf8))
        #expect(!json.contains("EXAMPLE0003891"))
        // ATA: the attributes are in the text report (they used to be missing).
        #expect(text.contains("Temperature"))
    }

    @Test @MainActor func serialIsMaskedInNVMeReportsAndKeptOnRequest() throws {
        let snapshot = DiskHealthSnapshot.nvme(Self.nvmeLog(), Self.identify)
        let disk = RealDisk(physical: Self.physical(.nvme), snapshot: snapshot, health: AppManager.evaluate(snapshot))
        let masked = ReportData(disk: disk, options: ExportOptions(includeSerial: false, includeHistory: false), benchmark: nil, history: .empty, generatedAt: Date())
        #expect(!String(decoding: try ExportService.reportJSON(masked), as: UTF8.self).contains("C02SECRET1234"))
        let shown = ReportData(disk: disk, options: ExportOptions(includeSerial: true, includeHistory: false), benchmark: nil, history: .empty, generatedAt: Date())
        #expect(ExportService.reportText(shown).contains("C02SECRET1234"))
    }

    @Test func unknownTemperatureIsNotReportedAsZero() {
        let disk = RealDisk(physical: Self.physical(.nvme), snapshot: .nvme(Self.nvmeLog(temperatureK: 0), Self.identify),
                            health: HealthAssessment(status: .good, healthPercent: 98, reasons: []))
        let summary = ExportService.summaryText(disk: disk)
        #expect(!summary.contains("0 °C") && !summary.contains("0\u{00A0}°C"))
        #expect(summary.contains("Temperature: Not reported"))
    }

    // MARK: Key indicators

    @Test func metricsFromNVMe() {
        let m = DiskMetrics(snapshot: .nvme(Self.nvmeLog(), Self.identify))
        #expect(m.temperatureC == 36)
        #expect(m.bytesWritten == 215_208_576 * 512_000)
        #expect(m.lifeRemainingPercent == 98)
        #expect(m.powerOnHours == 3440)
        #expect(m.badSectors == nil)
    }

    @Test func metricsFromATAPreferDriveTemperatureAndSurviveOverflow() {
        let snapshot = Self.ataSnapshot([
            Self.ataAttribute(0x05, raw: 2),
            Self.ataAttribute(0xAF, raw: 0xFFFF_FFFF_FFFF), // Host_Writes_MiB: 48 bits × 1 MiB overflows 64 bits
            Self.ataAttribute(0xBE, raw: 30),              // airflow
            Self.ataAttribute(0xC2, raw: 41),              // drive
            Self.ataAttribute(0xC5, raw: 1)
        ])
        let m = DiskMetrics(snapshot: .ata(snapshot))
        #expect(m.temperatureC == 41)
        #expect(m.bytesWritten == .max)
        #expect(m.badSectors == 3)
    }

    // MARK: Health engines

    @Test func lowLifeIsCautionLikeTheRedRing() {
        let health = HealthEngine.evaluate(smart: Self.nvmeLog(percentageUsed: 80), identify: Self.identify)
        #expect(health.status == .caution)
        #expect(health.healthPercent == 20)
        #expect(AmanPalette.level(health: health, capability: .supported) == .red)

        let fine = HealthEngine.evaluate(smart: Self.nvmeLog(percentageUsed: 60), identify: Self.identify)
        #expect(fine.status == .good)
    }

    @Test func heatDoesNotChangeHealthStatus() {
        let hot = NVMeSmartLog(criticalWarning: 0b10, compositeTemperatureKelvin: 358, availableSpare: 100, availableSpareThreshold: 10,
                               percentageUsed: 1, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0,
                               controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        #expect(HealthEngine.evaluate(smart: hot, identify: Self.identify).status == .good)
        #expect(TemperatureStatus.evaluate(temperatureCelsius: 85, identify: Self.identify) == .critical)
    }

    @Test func ataAttributeThatFailedInThePastIsCaution() {
        let snapshot = Self.ataSnapshot([Self.ataAttribute(0x09, current: 100, worst: 5, threshold: 10, raw: 100)])
        #expect(ATAHealthEvaluator.evaluate(snapshot: snapshot).status == .caution)
    }

    // MARK: History (append-only)

    @Test func historyIsAppendOnlyAndConvertsLegacyFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let historyDir = dir.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        let base = Date().addingTimeInterval(-3600)
        let legacy = [HistorySample(date: base, temperatureC: 30, percentageUsed: nil, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil)]
        try JSONEncoder().encode(legacy).write(to: historyDir.appendingPathComponent("K.json"))

        let store = HistoryStore(baseURL: dir)
        for i in 1...3 {
            store.record(HistorySample(date: base.addingTimeInterval(Double(i) * 30), temperatureC: 30 + i, percentageUsed: nil, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil), for: "K")
        }
        let samples = await store.loadSamples(for: "K", since: .distantPast)
        #expect(samples.map(\.temperatureC) == [30, 31, 32, 33])

        // Legacy file converted, then deleted; one line per reading.
        #expect(!FileManager.default.fileExists(atPath: historyDir.appendingPathComponent("K.json").path))
        let lines = try String(contentsOf: historyDir.appendingPathComponent("K.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 4)

        // A truncated line (power loss) doesn't prevent reading the rest.
        let handle = try FileHandle(forWritingTo: historyDir.appendingPathComponent("K.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"date\": 12".utf8))
        try handle.close()
        #expect(HistoryStore(baseURL: dir).samples(for: "K", since: .distantPast).count == 4)
    }

    @Test func aggregationBucketsAreAlignedOnTheClock() {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + 17 * 60) // 17 min past the hour
        let samples = (0..<120).map { i in
            HistorySample(date: start.addingTimeInterval(Double(i) * 30), temperatureC: 40, percentageUsed: nil, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil)
        }
        let points = HistoryAggregation.aggregate(samples: samples, range: .twentyFourHours).points
        #expect(points.allSatisfy { Int($0.date.timeIntervalSince1970 - 150) % 300 == 0 })
        #expect(Set(points.map(\.id)).count == points.count)
    }

    // MARK: Performance test

    @Test func benchmarkEstimatesAreHonest() {
        let gib: UInt64 = 1 << 30
        // File + 4 write tests × 5 passes, each at most the size of the file.
        #expect(BenchMath.maxBytesWritten(fileSize: gib, profile: .standard) == 21 * gib)
        #expect(BenchMath.maxBytesWritten(fileSize: gib, profile: .readOnly) == gib)
        let standard = BenchMath.estimatedMaxDuration(fileSize: gib, profile: .standard)
        #expect(standard > 200 && standard < 300)
        #expect(BenchMath.estimatedMaxDuration(fileSize: gib, profile: .quick) < standard)
    }

    @Test func benchmarkResultsAreFoundUnderLegacyKeys() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = BenchmarkHistoryManager(directoryURL: dir)
        let snapshot = DiskHealthSnapshot.nvme(Self.nvmeLog(), Self.identify)
        let disk = RealDisk(physical: Self.physical(.nvme), snapshot: snapshot, health: AppManager.evaluate(snapshot))

        func result(key: String, date: Date) -> BenchmarkResult {
            BenchmarkResult(id: UUID(), date: date, appVersion: "test", diskKey: key, profile: .quick, fileSize: 1 << 30,
                            conditions: BenchConditions(volumeName: "Macintosh HD", fileSystem: "APFS", encrypted: true, onBattery: false,
                                                        lowPowerMode: false, thermalStateStart: "nominal", temperatureStartC: 35,
                                                        temperatureMaxC: 40, bytesWritten: 1 << 30),
                            tests: [], completed: true, stopReason: nil)
        }
        // 0.9: saved under the hash of the model alone.
        manager.save(result(key: DiskIdentity.key(model: disk.physical.model, serial: ""), date: Date(timeIntervalSince1970: 1)))
        // 0.9.1: stable key, model + serial number.
        manager.save(result(key: disk.benchmarkKey, date: Date(timeIntervalSince1970: 2)))

        let found = await manager.loadResults(for: disk)
        #expect(found.count == 2)
        #expect(found.first?.date == Date(timeIntervalSince1970: 2))
    }

    // MARK: Miscellaneous

    @Test func diskFilterMatchesVolumesByPhysicalDisk() {
        let internalDisk = RealDisk(physical: Self.physical(.nvme), snapshot: nil, health: HealthAssessment(status: .unknown, healthPercent: nil, reasons: []))
        // Same volume name on an external drive: it must not be attached to this one.
        let volumes = [
            Volume(bsdName: "disk3s1", name: "Macintosh HD", mountPoint: "/", format: "APFS", totalBytes: 1, availableBytes: 1, physicalDiskBSDNames: ["disk0"]),
            Volume(bsdName: "disk9s1", name: "Macintosh HD", mountPoint: "/Volumes/Macintosh HD 1", format: "APFS", totalBytes: 1, availableBytes: 1, physicalDiskBSDNames: ["disk9"])
        ]
        let (_, filtered) = DiskFilter.filter(disks: [internalDisk], volumes: volumes)
        #expect(filtered.map(\.bsdName) == ["disk3s1"])
    }

    @Test func smartTableValuesCarryTheirUnits() {
        let rows = SmartRows.rows(for: .nvme(Self.nvmeLog(), Self.identify))
        #expect(rows.first { $0.id == 0x0C }?.value.hasSuffix("h") == true)
        #expect(rows.first { $0.id == 0x02 }?.value.hasSuffix("°C") == true)
        let ata = SmartRows.rows(for: .ata(Self.ataSnapshot([Self.ataAttribute(0x09, raw: 31_482)])))
        #expect(ata.first?.rawHex == "0x000000007AFA")
    }

    @Test func diagnosticMasksNestedSerialNumbers() {
        let props: [String: Any] = [
            "Device Characteristics": ["Product Name": "APPLE SSD SM0512G", "Serial Number": "EXAMPLE0003891"],
            "Protocol Characteristics": ["Physical Interconnect": "PCI"],
            "IOPlatformUUID": "12345678-1234-1234-1234-123456789ABC"
        ]
        let sanitized = IOKitDiagnostics.sanitizeProperties(props)
        let all = sanitized.values.joined(separator: " ")
        #expect(!all.contains("EXAMPLE0003891"))
        #expect(!all.contains("123456789ABC"))
        #expect(sanitized["Device Characteristics"]?.contains("APPLE SSD SM0512G") == true)
        #expect(sanitized["Protocol Characteristics"]?.contains("PCI") == true)
    }

    @Test func serialMasking() {
        #expect(SerialMasking.masked("EXAMPLE0003891") == "••••3891")
        #expect(SerialMasking.masked(nil) == "—")
        #expect(SerialMasking.masked("AB") == "••••")
    }
}
