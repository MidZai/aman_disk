import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct DriveConnectionTests {

    @Test func classifyInternalNVMe() {
        let pciDict: [String: Any] = [
            "Physical Interconnect": "PCI-Express",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: pciDict) == .internalNVMe)

        let appleFabricDict: [String: Any] = [
            "Physical Interconnect": "Apple Fabric",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: appleFabricDict) == .internalNVMe)
    }

    @Test func classifyInternalAHCI() {
        let ahciDict: [String: Any] = [
            "Physical Interconnect": "PCI-Express",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: ahciDict, protocolType: .pcieAhci) == .internalAHCI)

        let directAhci: [String: Any] = [
            "Physical Interconnect": "PCI-AHCI",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: directAhci) == .internalAHCI)
    }

    @Test func classifyInternalSATA() {
        let sataDict: [String: Any] = [
            "Physical Interconnect": "SATA",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: sataDict) == .internalSATA)
    }

    @Test func classifyThunderboltNVMe() {
        let tbPciDict: [String: Any] = [
            "Physical Interconnect": "PCI-Express",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: tbPciDict) == .thunderboltNVMe)

        let tbExplicit: [String: Any] = [
            "Physical Interconnect": "Thunderbolt",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: tbExplicit) == .thunderboltNVMe)
    }

    @Test func classifyUSB() {
        let usbDict: [String: Any] = [
            "Physical Interconnect": "USB",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: usbDict) == .usb)

        let uaspDict: [String: Any] = [
            "Physical Interconnect": "USB (Attached SCSI)",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: uaspDict) == .usb)

        let usbCDict: [String: Any] = [
            "Physical Interconnect": "USB-C",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: usbCDict) == .usb)
    }

    @Test func classifyUnknownAndMissingKeys() {
        // Missing dictionary with internal hint
        #expect(DriveClassifier.classify(protocolCharacteristics: nil, isInternalHint: true) == .internalNVMe)

        // Missing dictionary with external hint
        #expect(DriveClassifier.classify(protocolCharacteristics: nil, isInternalHint: false) == .other("External"))

        // Empty dictionary
        #expect(DriveClassifier.classify(protocolCharacteristics: [:], isInternalHint: false) == .other("External"))

        // Unknown interconnects
        let fcDict: [String: Any] = [
            "Physical Interconnect": "Fibre Channel",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: fcDict) == .other("Fibre Channel"))

        let fwDict: [String: Any] = [
            "Physical Interconnect": "FireWire 800",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.classify(protocolCharacteristics: fwDict) == .other("FireWire 800"))
    }

    @Test func filterExcludesVirtualAndRAMDisksAndImages() {
        // Disk image location "File"
        let dmgDict: [String: Any] = [
            "Physical Interconnect Location": "File"
        ]
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: dmgDict, bsdName: "disk2"))

        // Virtual interface
        let virtDict: [String: Any] = [
            "Physical Interconnect": "Virtual Interface"
        ]
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: virtDict, bsdName: "disk3"))

        // RAM Disk interconnect
        let ramDict: [String: Any] = [
            "Physical Interconnect": "RAM Disk"
        ]
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: ramDict, bsdName: "disk4"))

        // BSD name starting with "ram"
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: nil, bsdName: "ram0"))

        // Device protocol indicators
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: nil, deviceProtocol: "Disk Image", bsdName: "disk5"))
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: nil, deviceProtocol: "Virtual Interface", bsdName: "disk6"))
        #expect(!DriveClassifier.isPhysicalDrive(protocolCharacteristics: nil, deviceProtocol: "Network Disk", bsdName: "disk7"))

        // Valid physical drives
        let validInternal: [String: Any] = [
            "Physical Interconnect": "PCI-Express",
            "Physical Interconnect Location": "Internal"
        ]
        #expect(DriveClassifier.isPhysicalDrive(protocolCharacteristics: validInternal, bsdName: "disk0"))

        let validExternal: [String: Any] = [
            "Physical Interconnect": "USB",
            "Physical Interconnect Location": "External"
        ]
        #expect(DriveClassifier.isPhysicalDrive(protocolCharacteristics: validExternal, bsdName: "disk1"))
    }

    @Test func driveConnectionProperties() {
        #expect(!DriveConnection.internalNVMe.isExternal)
        #expect(!DriveConnection.internalAHCI.isExternal)
        #expect(!DriveConnection.internalSATA.isExternal)
        #expect(DriveConnection.thunderboltNVMe.isExternal)
        #expect(DriveConnection.usb.isExternal)
        #expect(DriveConnection.other("SCSI").isExternal)

        #expect(DriveConnection.internalNVMe.badgeLabel == "NVMe")
        #expect(DriveConnection.internalAHCI.badgeLabel == "PCIe AHCI")
        #expect(DriveConnection.internalSATA.badgeLabel == "SATA")
        #expect(DriveConnection.thunderboltNVMe.badgeLabel == "Thunderbolt")
        #expect(DriveConnection.usb.badgeLabel == "USB")
        #expect(DriveConnection.other("SCSI").badgeLabel == "SCSI")
    }

    @Test func physicalDiskCodableWithDriveConnection() throws {
        let original = PhysicalDisk(
            bsdName: "disk10",
            model: "OWC Envoy Pro FX",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .thunderboltNVMe,
            volumeNames: ["Thunderbolt Fast"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported,
            smartAvailability: .available
        )

        #expect(original.isExternal)
        #expect(original.driveConnection == .thunderboltNVMe)
        #expect(original.smartAvailability == .available)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhysicalDisk.self, from: data)

        #expect(decoded.bsdName == "disk10")
        #expect(decoded.isExternal)
        #expect(decoded.driveConnection == .thunderboltNVMe)
        #expect(decoded.smartAvailability == .available)
    }
}
