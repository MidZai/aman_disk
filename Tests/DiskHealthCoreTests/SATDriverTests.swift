import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct SATDriverTests {

    @Test func testATASmartPluginDetection() {
        // Uppercase user client UUID
        let upperPlugin: [String: Any] = [
            "24514B7A-2804-11D6-8A02-003065704866": "SATSMARTLib.plugin"
        ]
        #expect(ProtocolDetector.isATASmartPluginPresent(in: upperPlugin))

        // Lowercase user client UUID
        let lowerPlugin: [String: Any] = [
            "24514b7a-2804-11d6-8a02-003065704866": "IOATAFamily.kext/Contents/PlugIns/IOATALib.plugin"
        ]
        #expect(ProtocolDetector.isATASmartPluginPresent(in: lowerPlugin))

        // Factory ID
        let factoryPlugin: [String: Any] = [
            "5E659F92-20D3-11D6-BDB5-0003935A76B2": "IOATALib.plugin"
        ]
        #expect(ProtocolDetector.isATASmartPluginPresent(in: factoryPlugin))

        // Interface ID
        let interfacePlugin: [String: Any] = [
            "08abe21c-20d4-11d6-8df6-0003935a76b2": "IOATALib.plugin"
        ]
        #expect(ProtocolDetector.isATASmartPluginPresent(in: interfacePlugin))

        // Unrelated UUIDs
        let unrelatedPlugin: [String: Any] = [
            "9F76307B-84EC-49BE-A33D-761922A633F0": "SomeOtherLib.plugin",
            "00000000-0000-0000-0000-000000000000": "Dummy.plugin"
        ]
        #expect(!ProtocolDetector.isATASmartPluginPresent(in: unrelatedPlugin))

        // Empty dictionary
        #expect(!ProtocolDetector.isATASmartPluginPresent(in: [:]))
    }

    @Test func testSATTranslationActiveFlag() {
        // USB drive with ATA protocol and supported capability (SAT SMART Driver active)
        let satDrive = PhysicalDisk(
            bsdName: "disk11",
            model: "Seagate Expansion Desk",
            sizeBytes: 4_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["Backup"],
            usbVendorID: 0x0BC2,
            usbProductID: 0xAB30,
            protocolType: .ata,
            mediumType: .rotational,
            healthCapability: .supported,
            smartAvailability: .available
        )
        #expect(satDrive.isSATTranslationActive)
        #expect(satDrive.detailInterfaceLabel == "USB (SATA via SAT)")
        #expect(satDrive.driveConnection.badgeLabel == "USB")

        // USB drive without SAT (unsupported bridge)
        let usbNoSat = PhysicalDisk(
            bsdName: "disk12",
            model: "Crucial X8",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["Crucial"],
            usbVendorID: 0x0BDA,
            usbProductID: 0x9210,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge),
            smartAvailability: .notSupportedByEnclosure
        )
        #expect(!usbNoSat.isSATTranslationActive)
        #expect(usbNoSat.detailInterfaceLabel == "USB")
        #expect(usbNoSat.driveConnection.badgeLabel == "USB")

        // Thunderbolt NVMe drive
        let tbDrive = PhysicalDisk(
            bsdName: "disk10",
            model: "OWC Envoy Pro FX",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: ["Fast"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported,
            smartAvailability: .available
        )
        #expect(!tbDrive.isSATTranslationActive)
        #expect(tbDrive.isThunderbolt)
        #expect(tbDrive.detailInterfaceLabel == "Thunderbolt / USB4 (PCIe)")
        #expect(tbDrive.driveConnection.badgeLabel == "Thunderbolt")

        // Internal SATA drive
        let internalSATA = PhysicalDisk(
            bsdName: "disk0",
            model: "Crucial MX500",
            sizeBytes: 500_000_000_000,
            isInternal: true,
            driveConnection: .internalSATA,
            volumeNames: ["Macintosh HD"],
            protocolType: .ata,
            mediumType: .solidState,
            healthCapability: .supported,
            smartAvailability: .available
        )
        #expect(!internalSATA.isSATTranslationActive)
        #expect(internalSATA.detailInterfaceLabel == "SATA")
        #expect(internalSATA.driveConnection.badgeLabel == "SATA")
    }

    @Test func testSATSmartReadEvaluationAndParity() {
        // Build a simulated ATA snapshot on an external USB SAT drive
        let satDrive = PhysicalDisk(
            bsdName: "disk15",
            model: "WDC WD20EZAZ-00GGJB0",
            sizeBytes: 2_000_398_934_016,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["External SATA"],
            usbVendorID: 0x152D,
            usbProductID: 0x0578,
            usbVendorName: "JMicron",
            protocolType: .ata,
            mediumType: .rotational,
            healthCapability: .supported,
            smartAvailability: .available
        )

        #expect(satDrive.isSATTranslationActive)
        #expect(satDrive.detailInterfaceLabel == "USB (SATA via SAT)")
        #expect(satDrive.usbBridgeLabel?.contains("JMicron") == true)

        let attr5 = ATASmartAttribute(id: 5, flags: 0, current: 200, worst: 200, threshold: 140, raw: [0, 0, 0, 0, 0, 0], rawValue: 0)
        let attr194 = ATASmartAttribute(id: 194, flags: 0, current: 110, worst: 95, threshold: 0, raw: [33, 0, 0, 0, 0, 0], rawValue: 33)
        let attr197 = ATASmartAttribute(id: 197, flags: 0, current: 200, worst: 200, threshold: 0, raw: [0, 0, 0, 0, 0, 0], rawValue: 0)

        let snapshot = ATASmartSnapshot(
            attributes: [attr5, attr194, attr197],
            model: "WDC WD20EZAZ-00GGJB0",
            firmware: "80.00A80",
            serialNumber: "WD-WCC4M1234567",
            rotationRate: 5400,
            thresholdExceeded: false,
            checksumValid: true
        )

        let assessment = ATAHealthEvaluator.evaluate(snapshot: snapshot)
        #expect(assessment.status == .good)
    }

    @Test func testSATReadErrorAndDisconnectionHandling() {
        let physical = PhysicalDisk(
            bsdName: "disk16",
            model: "Toshiba Canvio Flex",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["Toshiba"],
            protocolType: .ata,
            mediumType: .rotational,
            healthCapability: .supported,
            smartAvailability: .available
        )

        // Simulated error when reading disconnected enclosure
        let disconnectedCode: Int32 = -536870212 // kIOReturnNotResponding
        let failedDisk = physical
            .withCapability(.unsupported(reason: .readFailed(code: "\(disconnectedCode)")))
            .withSmartAvailability(.error(code: disconnectedCode))

        #expect(failedDisk.healthCapability == .unsupported(reason: .readFailed(code: "\(disconnectedCode)")))
        #expect(failedDisk.smartAvailability == .error(code: disconnectedCode))
        #expect(failedDisk.isSATTranslationActive)

        // S.M.A.R.T. disabled on SAT drive
        let disabledDisk = physical
            .withCapability(.unsupported(reason: .smartDisabled))
            .withSmartAvailability(.disabledOnDrive)

        #expect(disabledDisk.healthCapability == .unsupported(reason: .smartDisabled))
        #expect(disabledDisk.smartAvailability == .disabledOnDrive)
    }
}
