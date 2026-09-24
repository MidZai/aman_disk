import Testing
import Foundation
@testable import DiskHealthCore

@Suite final class ParsingTests {
    @Test func testRealFixtureParsing() throws {
        let fixturePath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/disk0/smart.bin")
        
        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            Issue.record(Comment(rawValue: "Fixture not found at \(fixturePath.path)")); return
        }
        
        let data = try Data(contentsOf: fixturePath)
        let smartLog = NVMeSmartParser.parse(data)
        
        #expect(smartLog != nil)
        
        if let log = smartLog {
            #expect(log.temperatureCelsius == 28)
            #expect(log.percentageUsed == 0)
            #expect(log.dataUnitsRead == 27756904)
            #expect(log.dataUnitsWritten == 14747252)
            #expect(log.powerCycles == 151)
            #expect(log.powerOnHours == 268)
        }
    }
    @Test func testATAAppleParser() throws {
        let fixturePath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ata_apple_sm0512g")
        
        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            Issue.record(Comment(rawValue: "Fixture ata_apple_sm0512g not found")); return
        }
        
        let smartData = try Data(contentsOf: fixturePath.appendingPathComponent("smart.bin"))
        let thresholdsData = try Data(contentsOf: fixturePath.appendingPathComponent("thresholds.bin"))
        let identifyData = try Data(contentsOf: fixturePath.appendingPathComponent("identify.bin"))
        let referenceData = try Data(contentsOf: fixturePath.appendingPathComponent("reference.json"))
        
        let snapshot = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: false)
        #expect(snapshot != nil)
        
        struct RefInfo: Codable {
            let model_name: String
            let firmware_version: String
        }
        
        let ref = try JSONDecoder().decode(RefInfo.self, from: referenceData)
        #expect(snapshot?.model == ref.model_name)
        #expect(snapshot?.firmware == ref.firmware_version)
    }
}
