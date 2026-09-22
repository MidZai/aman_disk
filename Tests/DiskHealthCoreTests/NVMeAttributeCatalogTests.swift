import XCTest
@testable import DiskHealthCore

final class NVMeAttributeCatalogTests: XCTestCase {
    
    func testTemperatureStatus() {
        // No thresholds
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 20, identify: nil), .normal)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 60, identify: nil), .elevated)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 75, identify: nil), .critical)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: nil, identify: nil), .unknown)
        
        // With thresholds (Kelvin to Celsius: -273)
        // Warning = 338K (65C), Critical = 353K (80C)
        let identify = NVMeIdentify(serialNumber: "", modelNumber: "", firmwareRevision: "", warningTempKelvin: 338, criticalTempKelvin: 353, totalCapacityBytes: 0)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 60, identify: identify), .normal)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 70, identify: identify), .elevated)
        XCTAssertEqual(TemperatureStatus.evaluate(temperatureCelsius: 85, identify: identify), .critical)
    }
    
    func testRawValueFormatting() {
        func formatRaw(_ val: UInt64) -> String {
            return "0x\(String(format: "%02llX", val))"
        }
        
        XCTAssertEqual(formatRaw(0), "0x00")
        XCTAssertEqual(formatRaw(28), "0x1C")
        XCTAssertEqual(formatRaw(43_882_663_707), "0xA379C4F1B")
    }
    
    func testAttributeStates() {
        let identify = NVMeIdentify(serialNumber: "", modelNumber: "", firmwareRevision: "", warningTempKelvin: 338, criticalTempKelvin: 353, totalCapacityBytes: 0)
        
        // Normal log
        let normalLog = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 300, availableSpare: 100, availableSpareThreshold: 10, percentageUsed: 0, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let normalAttrs = NVMeAttributeCatalog.attributes(from: normalLog, identify: identify)
        
        XCTAssertEqual(normalAttrs.first { $0.id == 0x01 }?.state, .normal)
        XCTAssertEqual(normalAttrs.first { $0.id == 0x02 }?.state, .normal)
        XCTAssertEqual(normalAttrs.first { $0.id == 0x03 }?.state, .normal)
        XCTAssertEqual(normalAttrs.first { $0.id == 0x05 }?.state, .normal)
        XCTAssertEqual(normalAttrs.first { $0.id == 0x0E }?.state, .normal)
        
        // Critical log
        let critLog = NVMeSmartLog(criticalWarning: 1, compositeTemperatureKelvin: 360, availableSpare: 5, availableSpareThreshold: 10, percentageUsed: 105, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 10, errorLogEntries: 0)
        let critAttrs = NVMeAttributeCatalog.attributes(from: critLog, identify: identify)
        
        XCTAssertEqual(critAttrs.first { $0.id == 0x01 }?.state, .critical)
        XCTAssertEqual(critAttrs.first { $0.id == 0x02 }?.state, .critical)
        XCTAssertEqual(critAttrs.first { $0.id == 0x03 }?.state, .critical)
        XCTAssertEqual(critAttrs.first { $0.id == 0x05 }?.state, .critical)
        XCTAssertEqual(critAttrs.first { $0.id == 0x0E }?.state, .critical)
        
        // Warning log
        let warnLog = NVMeSmartLog(criticalWarning: 2, compositeTemperatureKelvin: 340, availableSpare: 15, availableSpareThreshold: 10, percentageUsed: 95, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let warnAttrs = NVMeAttributeCatalog.attributes(from: warnLog, identify: identify)
        
        XCTAssertEqual(warnAttrs.first { $0.id == 0x01 }?.state, .warning)
        XCTAssertEqual(warnAttrs.first { $0.id == 0x02 }?.state, .warning)
        XCTAssertEqual(warnAttrs.first { $0.id == 0x03 }?.state, .warning)
        XCTAssertEqual(warnAttrs.first { $0.id == 0x05 }?.state, .warning)
    }
}
