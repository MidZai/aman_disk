import Testing
import Foundation
@testable import DiskHealthCore

@Suite final class HistoryTests {
    var store: HistoryStore!
    var testKey: String = "TESTKEY"
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = HistoryStore(baseURL: tempDir)
    }
    
    deinit {
        try? FileManager.default.removeItem(atPath: store.folderPath())
    }
    
    @Test func testAppendAndRejectDuplicates() {
        let baseDate = Date()
        
        // Initial sample
        let s1 = HistorySample(date: baseDate, temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(s1, for: testKey)
        
        // Sample 2 mins later, temp = 30 -> Rejected (duplicate)
        let s2 = HistorySample(date: baseDate.addingTimeInterval(2 * 60), temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(s2, for: testKey)
        
        // Sample 2.5 mins later, temp = 33 -> Accepted (diff >= 3)
        let s3 = HistorySample(date: baseDate.addingTimeInterval(2.5 * 60), temperatureC: 33, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(s3, for: testKey)
        
        // Sample 7 mins later -> Accepted (diff time > 4 from s3)
        let s4 = HistorySample(date: baseDate.addingTimeInterval(7 * 60), temperatureC: 34, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(s4, for: testKey)
        
        let samples = store.samples(for: testKey, since: Date.distantPast)
        #expect(samples.count == 3)
        #expect(samples.last?.temperatureC == 34)
    }
    
    @Test func testPurgeOldSamples() {
        let baseDate = Date()
        let oldDate = baseDate.addingTimeInterval(-91 * 24 * 3600)
        
        let old = HistorySample(date: oldDate, temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(old, for: testKey)
        
        let new = HistorySample(date: baseDate, temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(new, for: testKey)
        
        let samples = store.samples(for: testKey, since: Date.distantPast)
        #expect(samples.count == 1)
        #expect(samples[0].date == baseDate)
    }
    
    @Test func testAggregation() {
        // Date alignée sur l'heure : les tranches de regroupement sont alignées sur l'horloge.
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        var samples: [HistorySample] = []
        
        // 1st hour: 12 samples (5 mins apart), temps = 30 to 41
        for i in 0..<12 {
            samples.append(HistorySample(date: baseDate.addingTimeInterval(Double(i) * 300), temperatureC: 30 + i, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100))
        }
        
        // Break of 3 hours (4 hours from baseDate)
        let baseDate2 = baseDate.addingTimeInterval(4 * 3600)
        
        // 2nd hour: 12 samples, temps = 20 to 31
        for i in 0..<12 {
            samples.append(HistorySample(date: baseDate2.addingTimeInterval(Double(i) * 300), temperatureC: 20 + i, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100))
        }
        
        let result1h = HistoryAggregation.aggregate(samples: samples, range: .oneHour)
        #expect(result1h.points.count == 24)
        #expect(result1h.points.first?.segment == 0)
        #expect(result1h.points.last?.segment == 1) // Should detect break
        
        let result7d = HistoryAggregation.aggregate(samples: samples, range: .sevenDays)
        // Aggregated per hour chunk -> 2 points
        #expect(result7d.points.count == 2)
        #expect(result7d.points[0].segment == 0)
        #expect(result7d.points[1].segment == 1) // Should detect segment break
        
        #expect(result7d.min == 20)
        #expect(result7d.max == 41)
        #expect(result7d.average == 31) // Avg of 20...41 is about 30.5 -> 31
    }
}
