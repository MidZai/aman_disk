import Foundation
import Testing
@testable import DiskHealthCore

/// Retention, compaction and gaps of the temperature history.
@Suite struct HistoryRetentionTests {
    // Multiple of 300 s: the 5-minute buckets line up exactly.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    
    func sample(_ date: Date, _ temp: Int) -> HistorySample {
        HistorySample(date: date, temperatureC: temp, percentageUsed: 1, dataUnitsWritten: nil, dataUnitsRead: nil, powerOnHours: nil, mediaErrors: nil, availableSpare: nil)
    }
    
    /// 48 h of readings every 30 s.
    func fortyEightHours() -> [HistorySample] {
        (0..<5760).map { i in
            sample(now.addingTimeInterval(-48 * 3600 + Double(i) * 30), 30 + (i % 10))
        }
    }
    
    @Test func compacting48HoursKeepsFullResolutionFor24Hours() {
        let result = HistoryStore.compact(fortyEightHours(), now: now)
        let cutoff = now.addingTimeInterval(-24 * 3600)
        let recent = result.filter { $0.date >= cutoff }
        let old = result.filter { $0.date < cutoff }
        
        // 24 h at 30 s = 2,880 raw readings; 24 h of 5-minute buckets = 288 points.
        #expect(recent.count == 2880)
        #expect(old.count == 288)
        #expect(result.count == 3168)
        #expect(recent.allSatisfy { !$0.isCompacted })
        
        // Each bucket: 10 readings (30..39 °C), min, average and max kept.
        #expect(old.allSatisfy { $0.sampleCount == 10 })
        #expect(old.allSatisfy { $0.temperatureMinC == 30 && $0.temperatureMaxC == 39 })
        #expect(old.allSatisfy { $0.temperatureC == 35 }) // 34.5 rounded
        // The total number of readings is preserved.
        #expect(result.reduce(0) { $0 + $1.measurementCount } == 5760)
    }
    
    @Test func compactionIsIdempotent() {
        let once = HistoryStore.compact(fortyEightHours(), now: now)
        let twice = HistoryStore.compact(once, now: now)
        #expect(once == twice)
        // An hour later, one more hour of raw readings is turned into buckets.
        let later = HistoryStore.compact(once, now: now.addingTimeInterval(3600))
        #expect(later.count == 3168 - 120 + 12)
    }
    
    @Test func samplesOlderThan30DaysAreRemoved() {
        let samples = [
            sample(now.addingTimeInterval(-31 * 24 * 3600), 30),
            sample(now.addingTimeInterval(-29 * 24 * 3600), 31),
            sample(now.addingTimeInterval(-60), 32)
        ]
        let result = HistoryStore.compact(samples, now: now)
        #expect(result.count == 2)
        #expect(result.first?.temperatureC == 31)
    }
    
    @Test func recordKeeps30SecondSamplesAndRejectsDuplicates() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(baseURL: dir)
        let base = Date()
        for i in 0..<10 {
            store.record(sample(base.addingTimeInterval(Double(i) * 30), 40), for: "K")
        }
        store.record(sample(base.addingTimeInterval(9 * 30 + 5), 40), for: "K") // duplicate
        #expect(store.samples(for: "K", since: .distantPast).count == 10)
    }
    
    @Test func legacyHistoryFilesAreStillReadable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let historyDir = dir.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        // v0.2 format: no min/max/sampleCount fields.
        let date = Date().addingTimeInterval(-3600).timeIntervalSinceReferenceDate
        let legacy = """
        [{"date": \(date), "temperatureC": 35, "percentageUsed": 2, "dataUnitsWritten": 1, "dataUnitsRead": 2, "powerOnHours": 100, "mediaErrors": 0, "availableSpare": 100},
         {"date": \(date + 300), "temperatureC": 37, "powerOnHours": 100}]
        """
        try legacy.write(to: historyDir.appendingPathComponent("OLD.json"), atomically: true, encoding: .utf8)
        
        let store = HistoryStore(baseURL: dir)
        let samples = store.samples(for: "OLD", since: .distantPast)
        #expect(samples.map(\.temperatureC) == [35, 37])
        #expect(samples.allSatisfy { $0.measurementCount == 1 })
        
        store.compactAll()
        #expect(store.samples(for: "OLD", since: .distantPast).count == 2)
    }
    
    @Test func gapLongerThanThreeIntervalsBreaksTheCurve() {
        var samples: [HistorySample] = []
        let start = now.addingTimeInterval(-3600)
        for i in 0..<20 { samples.append(sample(start.addingTimeInterval(Double(i) * 30), 40)) }
        // 10-minute gap, then readings resume.
        let resume = start.addingTimeInterval(19 * 30 + 600)
        for i in 0..<20 { samples.append(sample(resume.addingTimeInterval(Double(i) * 30), 41)) }
        // A 60 s gap (< 3 × 30 s) doesn't split the curve.
        samples.append(sample(resume.addingTimeInterval(19 * 30 + 60), 41))
        
        let agg = HistoryAggregation.aggregate(samples: samples, range: .oneHour)
        #expect(Set(agg.points.map(\.segment)) == [0, 1])
        #expect(agg.gaps.count == 1)
        #expect(agg.gaps.first?.duration == 600)
        #expect(agg.measurementCount == 41)
    }
    
    @Test func thirtyDayRangeShowsAverageWithMinMax() {
        let compacted = HistoryStore.compact(fortyEightHours(), now: now)
        let agg = HistoryAggregation.aggregate(samples: compacted, range: .thirtyDays)
        #expect(HistoryRange.thirtyDays.showsMinMaxBand)
        #expect(agg.min == 30)
        #expect(agg.max == 39)
        #expect(agg.measurementCount == 5760)
        #expect(agg.points.allSatisfy { $0.minTemperature == 30 && $0.maxTemperature == 39 })
        #expect(agg.gaps.isEmpty)
    }
}
