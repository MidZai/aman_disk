import XCTest
@testable import BenchmarkCore

final class ExportFormatTests: XCTestCase {
    func testDecodeV2() throws {
        let v2JSON = """
        {
            "schemaVersion": 2,
            "physical": {
                "bsdName": "disk1",
                "model": "Apple SSD",
                "connection": "nvmeInternal",
                "isInternal": true,
                "protocolType": "nvme",
                "sizeBytes": 1000000000,
                "mediumType": "solidState",
                "healthCapability": { "supported": {} },
                "volumeNames": []
            },
            "smart": null,
            "health": {
                "status": "good",
                "reasons": []
            },
            "lastRead": 725800000.0
        }
        """
        
        let data = v2JSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExportFormat.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertNil(decoded.benchmark)
        XCTAssertEqual(decoded.physical.model, "Apple SSD")
    }
}
