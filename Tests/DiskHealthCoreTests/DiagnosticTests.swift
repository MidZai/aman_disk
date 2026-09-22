import XCTest
@testable import DiskHealthCore

final class DiagnosticTests: XCTestCase {
    func testIOKitDiagnosticsMasking() {
        let rawProps: [String: Any] = [
            "Device Model": "Apple SSD SM0512G",
            "Serial Number": "C02412300ABCD",
            "UUID": "12345678-ABCD-EF01-2345-6789ABCDEF01",
            "media-guid": "98765432-10FE-DCBA-0987-654321FEDCBA",
            "RandomNumber": 42,
            "IsInternal": true,
            "RawUUIDValue": "11223344-5566-7788-99aa-bbccddeeff00"
        ]
        
        let sanitized = IOKitDiagnostics.sanitizeProperties(rawProps)
        
        XCTAssertEqual(sanitized["Device Model"], "Apple SSD SM0512G")
        XCTAssertEqual(sanitized["Serial Number"], "<masqué>")
        XCTAssertEqual(sanitized["UUID"], "<masqué>")
        XCTAssertEqual(sanitized["media-guid"], "<masqué>")
        XCTAssertEqual(sanitized["RandomNumber"], "42")
        XCTAssertEqual(sanitized["IsInternal"], "true")
        XCTAssertEqual(sanitized["RawUUIDValue"], "<masqué>")
    }
    
    func testDiagnosticEncodingDecoding() throws {
        let disk = PhysicalDisk(
            bsdName: "disk0",
            model: "APPLE SSD SM0512G",
            sizeBytes: 500_107_862_016,
            isInternal: true,
            connection: .nvmeInternal,
            volumeNames: ["Macintosh HD"],
            usbVendorID: nil,
            usbProductID: nil,
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .smartDisabled)
        )
        
        let mockNode = IOKitNodeDiagnostic(className: "IOBlockStorageDriver", properties: ["Clean": "Value"])
        let diag = Diagnostic(physical: disk, chain: [mockNode])
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let data = try encoder.encode(diag)
        let jsonStr = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(jsonStr.contains("\"bsd_name\" : \"disk0\""))
        XCTAssertTrue(jsonStr.contains("\"reason\" : \"smartDisabled\""))
        XCTAssertTrue(jsonStr.contains("\"protocol_type\" : \"nvme\""))
        XCTAssertTrue(jsonStr.contains("\"medium_type\" : \"solidState\""))
        XCTAssertTrue(jsonStr.contains("\"iokit_parent_chain\" : ["))
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Diagnostic.self, from: data)
        
        XCTAssertEqual(decoded.model, "APPLE SSD SM0512G")
        XCTAssertEqual(decoded.bsdName, "disk0")
        XCTAssertEqual(decoded.reason, "smartDisabled")
        XCTAssertEqual(decoded.iokitParentChain.count, 1)
        XCTAssertEqual(decoded.iokitParentChain[0].className, "IOBlockStorageDriver")
    }
    
    func testUnsupportedReasons() throws {
        let reasons: [UnsupportedReason] = [
            .usbBridge,
            .sdCardReader,
            .virtualDisk,
            .smartDisabled,
            .noSmartInterface,
            .readFailed(code: "-6")
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for reason in reasons {
            let data = try encoder.encode(reason)
            let decoded = try decoder.decode(UnsupportedReason.self, from: data)
            XCTAssertEqual(reason, decoded)
        }
        
        XCTAssertEqual(UnsupportedReason.usbBridge.rawValue, "usbBridge")
        XCTAssertEqual(UnsupportedReason.sdCardReader.rawValue, "sdCardReader")
        XCTAssertEqual(UnsupportedReason.virtualDisk.rawValue, "virtualDisk")
        XCTAssertEqual(UnsupportedReason.smartDisabled.rawValue, "smartDisabled")
        XCTAssertEqual(UnsupportedReason.noSmartInterface.rawValue, "noSmartInterface")
        XCTAssertEqual(UnsupportedReason.readFailed(code: "-6").rawValue, "readFailed(-6)")
    }
}
