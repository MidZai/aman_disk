import Testing
import Foundation
@testable import DiskHealthCore

/// Outputs frozen before the engine was made buildable for macOS 10.13 (Aman Legacy):
/// the replacements of macOS 10.15+ APIs must not change anything the apps read or write.
@Suite struct LegacyCompatTests {
    /// The key names the history and event files: a different hash would orphan every drive's history.
    @Test func diskIdentityKeysAreUnchanged() {
        #expect(DiskIdentity.key(model: "Samsung SSD 860 EVO 500GB", serial: "S3Z2NB0K123456A") == "59923f13d29936d4")
        #expect(DiskIdentity.key(model: "APPLE SSD AP0512M", serial: "") == "55000dfa74b6176c")
        #expect(DiskIdentity.key(model: "Crucial X8", serial: "CRUCIAL12345") == "d79a0b3c09868eda")
        #expect(DiskIdentity.key(model: "WDC WD10EZEX-08WN4A0", serial: "WD-WCC6Y1234567") == "32a315f1a2df6f62")
    }

    /// Appending to an existing event file keeps the earlier lines (one JSON object per line).
    @Test func eventLogAppendsLines() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let log = DiskEventLog(baseURL: base)
        let first = DiskEvent(date: Date(timeIntervalSince1970: 1_000), kind: .smartEnabled)
        let second = DiskEvent(date: Date(timeIntervalSince1970: 2_000), kind: .smartEnabled)
        log.append(first, for: "KEY")
        log.append(second, for: "KEY")
        #expect(log.events(for: "KEY") == [first, second])

        let file = base.appendingPathComponent("Events/KEY.jsonl")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
    }

    /// Appending to an existing history file keeps the earlier samples.
    @Test func historyAppendsToExistingFile() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        // Recent dates: older readings would be purged by the retention rule.
        let start = Date().addingTimeInterval(-7_200).rounded()
        let first = HistorySample(date: start, temperatureC: 30, percentageUsed: 1, dataUnitsWritten: 10, dataUnitsRead: 10, powerOnHours: 5, mediaErrors: 0, availableSpare: 100)
        let second = HistorySample(date: start.addingTimeInterval(3_600), temperatureC: 40, percentageUsed: 1, dataUnitsWritten: 11, dataUnitsRead: 11, powerOnHours: 6, mediaErrors: 0, availableSpare: 100)
        // append() is asynchronous: samples(for:since:) on the same store waits for it.
        let creator = HistoryStore(baseURL: base)
        creator.append(first, for: "KEY")
        _ = creator.samples(for: "KEY", since: .distantPast)
        // A new store finds the file and appends a line to it.
        let appender = HistoryStore(baseURL: base)
        appender.append(second, for: "KEY")
        _ = appender.samples(for: "KEY", since: .distantPast)
        // A third store reads only what reached the disk.
        let reread = HistoryStore(baseURL: base).samples(for: "KEY", since: .distantPast)
        #expect(reread.map(\.date) == [first.date, second.date])
    }
}

private extension Date {
    /// Whole seconds: the history file stores dates as JSON numbers.
    func rounded() -> Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}
