import XCTest
@testable import DiskHealthCore

final class HealthEngineTests: XCTestCase {
    
    private func makeSmartLog(
        percentageUsed: UInt8 = 0,
        availableSpare: UInt8 = 100,
        threshold: UInt8 = 10,
        mediaErrors: UInt64 = 0,
        criticalWarning: UInt8 = 0,
        temperatureKelvin: UInt16 = 300
    ) -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        
        buffer[0] = criticalWarning
        
        var tempK = temperatureKelvin.littleEndian
        withUnsafeBytes(of: &tempK) { buffer.replaceSubrange(1..<3, with: $0) }
        
        buffer[3] = availableSpare
        buffer[4] = threshold
        buffer[5] = percentageUsed
        
        var mErr = mediaErrors.littleEndian
        withUnsafeBytes(of: &mErr) { buffer.replaceSubrange(160..<168, with: $0) }
        
        return Data(buffer)
    }
    
    private func defaultIdentify() -> NVMeIdentify {
        return NVMeIdentify(
            serialNumber: "SN123",
            modelNumber: "TEST DISK",
            firmwareRevision: "1.0",
            warningTempKelvin: 0,
            criticalTempKelvin: 0,
            totalCapacityBytes: 1000
        )
    }

    func testHealthEngine_Good() {
        let data = makeSmartLog(percentageUsed: 0)
        let smartLog = NVMeSmartParser.parse(data)!
        let identify = defaultIdentify()
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
        XCTAssertEqual(assessment.status, .good)
        XCTAssertEqual(assessment.healthPercent, 100)
    }
    
    func testHealthEngine_GoodWithSlightWear() {
        let data = makeSmartLog(percentageUsed: 2)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .good)
        XCTAssertEqual(assessment.healthPercent, 98)
    }
    
    func testHealthEngine_CautionWear() {
        let data = makeSmartLog(percentageUsed: 91)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .caution)
        XCTAssertEqual(assessment.healthPercent, 9)
    }
    
    func testHealthEngine_CautionMediaErrors() {
        let data = makeSmartLog(mediaErrors: 1)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .caution)
    }
    
    func testHealthEngine_BadAvailableSpare() {
        let data = makeSmartLog(availableSpare: 4, threshold: 10)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .bad)
    }
    
    func testHealthEngine_BadCriticalWarningReadOnly() {
        // bit 3 = read only = 0x08
        let data = makeSmartLog(criticalWarning: 0b0000_1000)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .bad)
    }
    
    func testHealthEngine_PercentageUsedClamped() {
        let data = makeSmartLog(percentageUsed: 150)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        // status may be .caution due to wear >= 90
        XCTAssertEqual(assessment.status, .caution)
        XCTAssertEqual(assessment.healthPercent, 0)
    }
    
    func testHealthEngine_PercentageUsedTooHighDoesNotCrash() {
        let data = makeSmartLog(percentageUsed: 255)
        let smartLog = NVMeSmartParser.parse(data)!
        
        let assessment = HealthEngine.evaluate(smart: smartLog, identify: defaultIdentify())
        XCTAssertEqual(assessment.status, .caution)
        XCTAssertEqual(assessment.healthPercent, 0)
    }
}
