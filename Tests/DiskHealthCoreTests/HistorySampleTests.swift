import Testing
import Foundation
@testable import DiskHealthCore

@Suite final class HistorySampleTests {
    @Test func testLegacyHistorySampleDecoding() throws {
        let legacyJSON = """
        {
            "date": 718300000,
            "temperatureC": 35,
            "percentageUsed": 2,
            "dataUnitsWritten": 12345,
            "dataUnitsRead": 67890,
            "powerOnHours": 100,
            "mediaErrors": 0,
            "availableSpare": 100
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let sample = try decoder.decode(HistorySample.self, from: legacyJSON)
        
        #expect(sample.temperatureC == 35)
        #expect(sample.percentageUsed == 2)
        #expect(sample.dataUnitsWritten == 12345)
    }
    
    @Test func testATAHistorySampleDecoding() throws {
        let newJSON = """
        {
            "date": 718300000,
            "temperatureC": 35,
            "powerOnHours": 100
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let sample = try decoder.decode(HistorySample.self, from: newJSON)
        
        #expect(sample.temperatureC == 35)
        #expect(sample.percentageUsed == nil)
        #expect(sample.powerOnHours == 100)
    }
}
