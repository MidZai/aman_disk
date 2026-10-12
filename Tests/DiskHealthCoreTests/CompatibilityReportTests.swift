import Testing
import Foundation
@testable import DiskHealthCore

@Suite final class CompatibilityReportTests {
    @Test func testAnonymizationSerialNeverInOutput() throws {
        let inputSerial = "WD-WCC4N987654321"
        let confidentialVolume = "SuperConfidentialProject"
        let secretUserPath = "/Users/secretcoder/aman"
        
        let physical = PhysicalDisk(
            bsdName: "disk4",
            model: "WD My Passport 2627",
            sizeBytes: 2_000_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: [confidentialVolume],
            usbVendorID: 0x1058,
            usbProductID: 0x2627,
            usbVendorName: "Western Digital",
            usbProductName: "My Passport",
            usbLinkSpeedBps: 5_000_000_000,
            usbBcdUSB: 0x0320,
            usbIsUAS: true,
            protocolType: .usb,
            mediumType: .rotational,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        
        let mockNode = IOKitNodeDiagnostic(
            className: "IOBlockStorageDriver",
            properties: [
                "Device Characteristics": "{Product Name=My Passport, Serial Number=\(inputSerial)}",
                "DebugPath": secretUserPath,
                "IOPlatformUUID": "11223344-5566-7788-99AA-BBCCDDEEFF00"
            ]
        )
        
        var report = CompatibilityReport.collect(physical: physical, snapshot: nil, amanVersion: "0.9.7")
        // Force mock parent chain containing raw secret properties to test JSON sanitization
        report = CompatibilityReport(
            amanVersion: report.amanVersion,
            macosVersion: report.macosVersion,
            architecture: report.architecture,
            model: report.model,
            bsdName: report.bsdName,
            connection: report.connection,
            storageDriver: report.storageDriver,
            smartAvailability: report.smartAvailability,
            errorCode: report.errorCode,
            satTranslationActive: report.satTranslationActive,
            protocolCharacteristics: report.protocolCharacteristics,
            deviceCharacteristics: [
                "Product Name": "My Passport",
                "Serial Number": inputSerial
            ],
            usbHostDevice: report.usbHostDevice,
            rawSmartAttributes: report.rawSmartAttributes,
            iokitParentChain: [mockNode]
        )
        
        let jsonData = try CompatibilityReport.generateJSON(report: report, knownSerials: [inputSerial])
        let jsonStr = try #require(String(data: jsonData, encoding: .utf8))
        
        // Acceptance criterion: serial number present in input must NEVER appear anywhere in output
        #expect(!jsonStr.contains(inputSerial))
        #expect(jsonStr.contains("<masqué>"))
        
        // Acceptance criterion: no volume names, no user paths
        #expect(!jsonStr.contains(confidentialVolume))
        #expect(!jsonStr.contains("/Users/secretcoder"))
        
        // Assert the generated JSON can be decoded back
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(CompatibilityReport.self, from: jsonData)
        
        #expect(decoded.model == "WD My Passport 2627")
        #expect(decoded.bsdName == "disk4")
        #expect(decoded.amanVersion == "0.9.7")
        #expect(decoded.deviceCharacteristics?["Serial Number"] == "<masqué>")
    }

    @Test func testCompatibilityReportFields() throws {
        let physical = PhysicalDisk(
            bsdName: "disk5",
            model: "Samsung PSSD T7",
            sizeBytes: 1_000_204_886_016,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: [],
            usbVendorID: 0x04E8,
            usbProductID: 0x61F5,
            usbVendorName: "Samsung",
            usbProductName: "PSSD T7",
            usbLinkSpeedBps: 10_000_000_000,
            usbBcdUSB: 0x0320,
            usbIsUAS: true,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .supported
        )
        
        let dummyAttr = ATASmartAttribute(id: 0x05, flags: 0x0033, current: 100, worst: 100, threshold: 10, raw: [0, 0, 0, 0, 0, 0], rawValue: 0)
        let ataSnapshot = ATASmartSnapshot(
            attributes: [dummyAttr],
            model: "Samsung PSSD T7",
            firmware: "FXT001",
            serialNumber: "S43TNB0N123456F",
            rotationRate: 0,
            thresholdExceeded: false,
            checksumValid: true
        )
        
        let report = CompatibilityReport.collect(
            physical: physical,
            snapshot: .ata(ataSnapshot),
            amanVersion: "0.9.7"
        )
        
        let jsonData = try CompatibilityReport.generateJSON(report: report, knownSerials: ["S43TNB0N123456F"])
        let jsonStr = try #require(String(data: jsonData, encoding: .utf8))
        
        // Serial must not appear
        #expect(!jsonStr.contains("S43TNB0N123456F"))
        
        // Required fields in JSON (snake_case)
        #expect(jsonStr.contains("\"aman_version\""))
        #expect(jsonStr.contains("\"macos_version\""))
        #expect(jsonStr.contains("\"architecture\""))
        #expect(jsonStr.contains("\"model\""))
        #expect(jsonStr.contains("\"bsd_name\""))
        #expect(jsonStr.contains("\"storage_driver\""))
        #expect(jsonStr.contains("\"smart_availability\""))
        #expect(jsonStr.contains("\"sat_translation_active\""))
        #expect(jsonStr.contains("\"protocol_characteristics\""))
        #expect(jsonStr.contains("\"device_characteristics\""))
        #expect(jsonStr.contains("\"usb_host_device\""))
        #expect(jsonStr.contains("\"raw_smart_attributes\""))
        
        // Verify attribute is present
        #expect(jsonStr.contains("\"raw_value\" : 0"))
        #expect(jsonStr.contains("\"key\" : \"0x05\""))
    }
}

// Review fixes: an unsupported drive has no snapshot, its serial comes from the physical description.
extension CompatibilityReportTests {
    @Test func physicalSerialIsMaskedWithoutSnapshot() throws {
        let serial = "WD-WCC4N987654321"
        let physical = PhysicalDisk(
            bsdName: "disk4", model: "WD My Passport 2627", sizeBytes: 2_000_000_000_000, isInternal: false,
            connection: .usb, driveConnection: .usb, volumeNames: [], protocolType: .usb, mediumType: .rotational,
            healthCapability: .unsupported(reason: .usbBridge), serialNumber: serial
        )
        let collected = CompatibilityReport.collect(physical: physical, snapshot: nil, amanVersion: "1.0.0")
        let report = CompatibilityReport(
            amanVersion: collected.amanVersion, macosVersion: collected.macosVersion, architecture: collected.architecture,
            model: collected.model, bsdName: collected.bsdName, connection: collected.connection,
            storageDriver: collected.storageDriver, smartAvailability: collected.smartAvailability,
            errorCode: collected.errorCode, satTranslationActive: collected.satTranslationActive,
            protocolCharacteristics: collected.protocolCharacteristics,
            deviceCharacteristics: ["Product Name": "My Passport", "Serial Number": serial],
            usbHostDevice: collected.usbHostDevice, rawSmartAttributes: collected.rawSmartAttributes,
            iokitParentChain: collected.iokitParentChain
        )
        let serials = CompatibilityReport.serialsToMask(physical: physical, snapshot: nil)
        #expect(serials == [serial])
        let json = try #require(String(data: CompatibilityReport.generateJSON(report: report, knownSerials: serials), encoding: .utf8))
        #expect(!json.contains(serial))
    }
}
