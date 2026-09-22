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
}
