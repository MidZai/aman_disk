import XCTest
@testable import DiskHealthCore
import Foundation

final class ParsingTests: XCTestCase {
    func testRealFixtureParsing() throws {
        let fixturePath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/disk0/smart.bin")
        
        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            throw XCTSkip("Fixture not found at \(fixturePath.path)")
        }
        
        let data = try Data(contentsOf: fixturePath)
        let smartLog = NVMeSmartParser.parse(data)
        
        XCTAssertNotNil(smartLog)
        
        if let log = smartLog {
            XCTAssertEqual(log.temperatureCelsius, 28)
            XCTAssertEqual(log.percentageUsed, 0)
            XCTAssertEqual(log.dataUnitsRead, 27756904)
            XCTAssertEqual(log.dataUnitsWritten, 14747252)
            XCTAssertEqual(log.powerCycles, 151)
            XCTAssertEqual(log.powerOnHours, 268)
        }
    }
    func testATAAppleParser() throws {
        let fixturePath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ata_apple_sm0512g")
        
        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            throw XCTSkip("Fixture ata_apple_sm0512g not found")
        }
        
        let smartData = try Data(contentsOf: fixturePath.appendingPathComponent("smart.bin"))
        let thresholdsData = try Data(contentsOf: fixturePath.appendingPathComponent("thresholds.bin"))
        let identifyData = try Data(contentsOf: fixturePath.appendingPathComponent("identify.bin"))
        let referenceData = try Data(contentsOf: fixturePath.appendingPathComponent("reference.json"))
        
        let snapshot = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: false)
        XCTAssertNotNil(snapshot)
        
        struct RefInfo: Codable {
            let model_name: String
            let firmware_version: String
        }
        
        let ref = try JSONDecoder().decode(RefInfo.self, from: referenceData)
        XCTAssertEqual(snapshot?.model, ref.model_name)
        XCTAssertEqual(snapshot?.firmware, ref.firmware_version)
    }
}
