import Testing
import Foundation
@testable import DiskHealthCore

@Suite final class DiagnosticTests {
    @Test func testIOKitDiagnosticsMasking() {
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
        
        #expect(sanitized["Device Model"] == "Apple SSD SM0512G")
        #expect(sanitized["Serial Number"] == "<masqué>")
        #expect(sanitized["UUID"] == "<masqué>")
        #expect(sanitized["media-guid"] == "<masqué>")
        #expect(sanitized["RandomNumber"] == "42")
        #expect(sanitized["IsInternal"] == "true")
        #expect(sanitized["RawUUIDValue"] == "<masqué>")
    }
    
    @Test func testDiagnosticEncodingDecoding() throws {
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
        
        #expect(jsonStr.contains("\"bsd_name\" : \"disk0\""))
        #expect(jsonStr.contains("\"reason\" : \"smartDisabled\""))
        #expect(jsonStr.contains("\"protocol_type\" : \"nvme\""))
        #expect(jsonStr.contains("\"medium_type\" : \"solidState\""))
        #expect(jsonStr.contains("\"iokit_parent_chain\" : ["))
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Diagnostic.self, from: data)
        
        #expect(decoded.model == "APPLE SSD SM0512G")
        #expect(decoded.bsdName == "disk0")
        #expect(decoded.reason == "smartDisabled")
        #expect(decoded.iokitParentChain.count == 1)
        #expect(decoded.iokitParentChain[0].className == "IOBlockStorageDriver")
    }
    
    @Test func testUnsupportedReasons() throws {
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
            #expect(reason == decoded)
        }
        
        #expect(UnsupportedReason.usbBridge.rawValue == "usbBridge")
        #expect(UnsupportedReason.sdCardReader.rawValue == "sdCardReader")
        #expect(UnsupportedReason.virtualDisk.rawValue == "virtualDisk")
        #expect(UnsupportedReason.smartDisabled.rawValue == "smartDisabled")
        #expect(UnsupportedReason.noSmartInterface.rawValue == "noSmartInterface")
        #expect(UnsupportedReason.readFailed(code: "-6").rawValue == "readFailed(-6)")
    }
}
