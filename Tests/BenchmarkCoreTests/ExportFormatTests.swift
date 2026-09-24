import Testing
import Foundation
@testable import BenchmarkCore

@Suite final class ExportFormatTests {
    @Test func testDecodeV2() throws {
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
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.benchmark == nil)
        #expect(decoded.physical.model == "Apple SSD")
    }
}
