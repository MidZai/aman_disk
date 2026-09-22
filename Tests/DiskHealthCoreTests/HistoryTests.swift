import XCTest
@testable import DiskHealthCore

final class HistoryTests: XCTestCase {
    var store: HistoryStore!
    var testKey: String = "TESTKEY"
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = HistoryStore(baseURL: tempDir)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: store.folderPath())
        super.tearDown()
    }
    
    func testAppendAndRejectDuplicates() {
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
        
        // Sample 5 mins later -> Accepted (diff time > 4)
        let s4 = HistorySample(date: baseDate.addingTimeInterval(5 * 60), temperatureC: 34, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(s4, for: testKey)
        
        let samples = store.samples(for: testKey, since: Date.distantPast)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.last?.temperatureC, 34)
    }
    
    func testPurgeOldSamples() {
        let baseDate = Date()
        let oldDate = baseDate.addingTimeInterval(-91 * 24 * 3600)
        
        let old = HistorySample(date: oldDate, temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(old, for: testKey)
        
        let new = HistorySample(date: baseDate, temperatureC: 30, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100)
        store.append(new, for: testKey)
        
        let samples = store.samples(for: testKey, since: Date.distantPast)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].date, baseDate)
    }
    
    func testAggregation() {
        let baseDate = Date()
        var samples: [HistorySample] = []
        
        // 1st hour: 12 samples (5 mins apart), temps = 30 to 41
        for i in 0..<12 {
            samples.append(HistorySample(date: baseDate.addingTimeInterval(Double(i) * 300), temperatureC: 30 + i, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100))
        }
        
        // Break of 2 hours
        let baseDate2 = baseDate.addingTimeInterval(3 * 3600)
        
        // 2nd hour: 12 samples, temps = 20 to 31
        for i in 0..<12 {
            samples.append(HistorySample(date: baseDate2.addingTimeInterval(Double(i) * 300), temperatureC: 20 + i, percentageUsed: 0, dataUnitsWritten: 0, dataUnitsRead: 0, powerOnHours: 0, mediaErrors: 0, availableSpare: 100))
        }
        
        let result1h = HistoryAggregation.aggregate(samples: samples, range: .oneHour)
        XCTAssertEqual(result1h.points.count, 24)
        XCTAssertEqual(result1h.points.first?.segment, 0)
        XCTAssertEqual(result1h.points.last?.segment, 1) // Should detect break
        
        let result7d = HistoryAggregation.aggregate(samples: samples, range: .sevenDays)
        // Aggregated per hour chunk -> 2 points
        XCTAssertEqual(result7d.points.count, 2)
        XCTAssertEqual(result7d.points[0].segment, 0)
        XCTAssertEqual(result7d.points[1].segment, 1) // Should detect segment break
        
        XCTAssertEqual(result7d.min, 20)
        XCTAssertEqual(result7d.max, 41)
        XCTAssertEqual(result7d.average, 30) // Avg of 20...41 is about 30.5 -> 30
    }
}
