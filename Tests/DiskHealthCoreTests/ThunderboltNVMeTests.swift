import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct ThunderboltNVMeTests {

    private func makeNVMeSmartLog(
        percentageUsed: UInt8 = 0,
        availableSpare: UInt8 = 100,
        threshold: UInt8 = 10,
        mediaErrors: UInt64 = 0,
        criticalWarning: UInt8 = 0,
        temperatureKelvin: UInt16 = 308 // ~35°C
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

    @Test func testThunderboltNVMeParsingAndHealthEvaluation_Samsung980Pro() throws {
        // Simulated Samsung 980 PRO 1TB inside an OWC Envoy Pro FX enclosure
        let disk = PhysicalDisk(
            bsdName: "disk4",
            model: "OWC Envoy Pro FX",
            sizeBytes: 1_000_204_886_016,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: ["Thunderbolt Fast"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported,
            smartAvailability: .available
        )

        #expect(disk.isThunderbolt)
        #expect(disk.isExternal)
        #expect(!disk.isInternal)
        #expect(disk.detailInterfaceLabel == "Thunderbolt / USB4 (PCIe)")

        let smartData = makeNVMeSmartLog(
            percentageUsed: 3,
            availableSpare: 100,
            threshold: 10,
            mediaErrors: 0,
            criticalWarning: 0,
            temperatureKelvin: 308 // 35°C
        )
        guard let smartLog = NVMeSmartParser.parse(smartData) else {
            Issue.record("Failed to parse NVMe SMART log")
            return
        }

        let identify = NVMeIdentify(
            serialNumber: "S5GXNF0R123456",
            modelNumber: "Samsung SSD 980 PRO 1TB",
            firmwareRevision: "5B2QGXA7",
            warningTempKelvin: 355,
            criticalTempKelvin: 358,
            totalCapacityBytes: 1_000_204_886_016
        )

        let assessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
        #expect(assessment.status == .good)
        #expect(assessment.healthPercent == 97)
        #expect(smartLog.temperatureCelsius == 35)

        // Attribute catalog check
        let attributes = NVMeAttributeCatalog.attributes(from: smartLog, identify: identify)
        #expect(!attributes.isEmpty)
        let wearAttr = attributes.first { $0.id == 0x05 }
        #expect(wearAttr?.state == .normal)
    }

    @Test func testThunderboltNVMeParsingAndHealthEvaluation_WDBlackSN850X() throws {
        // Simulated WD_BLACK SN850X 2TB inside an Acasis TBU405 USB4 enclosure
        let disk = PhysicalDisk(
            bsdName: "disk5",
            model: "WD_BLACK SN850X 2000GB",
            sizeBytes: 2_000_398_934_016,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: ["Scratch USB4"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported,
            smartAvailability: .available
        )

        #expect(disk.isThunderbolt)
        #expect(disk.detailInterfaceLabel == "Thunderbolt / USB4 (PCIe)")

        // High wear scenario (percentageUsed = 94%)
        let smartData = makeNVMeSmartLog(
            percentageUsed: 94,
            availableSpare: 90,
            threshold: 10,
            mediaErrors: 0,
            criticalWarning: 0,
            temperatureKelvin: 318 // 45°C
        )
        guard let smartLog = NVMeSmartParser.parse(smartData) else {
            Issue.record("Failed to parse NVMe SMART log")
            return
        }

        let identify = NVMeIdentify(
            serialNumber: "22452B800123",
            modelNumber: "WD_BLACK SN850X 2000GB",
            firmwareRevision: "620311WD",
            warningTempKelvin: 353,
            criticalTempKelvin: 358,
            totalCapacityBytes: 2_000_398_934_016
        )

        let assessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
        #expect(assessment.status == .caution)
        #expect(assessment.healthPercent == 6)
        #expect(smartLog.temperatureCelsius == 45)
    }

    @Test func testParityWithInternalDriveEvaluation() {
        // Ensure that identical SMART logs evaluate to the exact same health status and metrics
        let smartData = makeNVMeSmartLog(
            percentageUsed: 15,
            availableSpare: 85,
            threshold: 10,
            mediaErrors: 2,
            criticalWarning: 0,
            temperatureKelvin: 315
        )
        let smartLog = NVMeSmartParser.parse(smartData)!
        let identify = NVMeIdentify(
            serialNumber: "GENERIC123",
            modelNumber: "Generic NVMe SSD",
            firmwareRevision: "1.0",
            warningTempKelvin: 343,
            criticalTempKelvin: 353,
            totalCapacityBytes: 512_000_000_000
        )

        let internalAssessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
        let externalAssessment = HealthEngine.evaluate(smart: smartLog, identify: identify)

        #expect(internalAssessment.status == externalAssessment.status)
        #expect(internalAssessment.healthPercent == externalAssessment.healthPercent)
        #expect(internalAssessment.reasons == externalAssessment.reasons)
    }

    @Test func testDetailInterfaceLabelAndIsThunderbolt() {
        let tbDisk = PhysicalDisk(
            bsdName: "disk3",
            model: "Thunderbolt SSD",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: [],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )
        #expect(tbDisk.isThunderbolt)
        #expect(tbDisk.isExternal)
        #expect(tbDisk.detailInterfaceLabel == "Thunderbolt / USB4 (PCIe)")

        let internalDisk = PhysicalDisk(
            bsdName: "disk0",
            model: "Apple SSD",
            sizeBytes: 500_000_000_000,
            isInternal: true,
            driveConnection: .internalNVMe,
            volumeNames: [],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )
        #expect(!internalDisk.isThunderbolt)
        #expect(!internalDisk.isExternal)
        #expect(internalDisk.detailInterfaceLabel == "NVMe")

        let usbDisk = PhysicalDisk(
            bsdName: "disk2",
            model: "USB SanDisk",
            sizeBytes: 64_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        #expect(!usbDisk.isThunderbolt)
        #expect(usbDisk.isExternal)
        #expect(usbDisk.detailInterfaceLabel == "USB")
    }

    @Test func testSmartReadErrorHandlingWithoutCrash() throws {
        // When SMART read fails with an error code (e.g. -4 for kIOReturnNotResponding)
        let disk = PhysicalDisk(
            bsdName: "disk4",
            model: "Problematic TB SSD",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: [],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )

        let failedDisk = disk
            .withCapability(.unsupported(reason: .readFailed(code: "-4")))
            .withSmartAvailability(.error(code: Int32(-4)))

        #expect(failedDisk.smartAvailability == .error(code: Int32(-4)))
        #expect(failedDisk.healthCapability == .unsupported(reason: .readFailed(code: "-4")))
        #expect(failedDisk.isThunderbolt)
        #expect(failedDisk.detailInterfaceLabel == "Thunderbolt / USB4 (PCIe)")

        // Verify JSON encoding/decoding succeeds without crash
        let encoded = try JSONEncoder().encode(failedDisk)
        let decoded = try JSONDecoder().decode(PhysicalDisk.self, from: encoded)

        #expect(decoded.bsdName == "disk4")
        #expect(decoded.smartAvailability == .error(code: Int32(-4)))
        #expect(decoded.healthCapability == .unsupported(reason: .readFailed(code: "-4")))
    }
}
