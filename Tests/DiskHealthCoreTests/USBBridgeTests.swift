import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct USBBridgeTests {

    @Test func testKnownBridgeLookup() {
        let db = USBBridgeDatabase.shared

        #expect(db.vendorName(for: 0x152D) == "JMicron")
        #expect(db.vendorName(for: 0x174C) == "ASMedia")
        #expect(db.vendorName(for: 0x0BDA) == "Realtek")

        #expect(db.formatChip(vendorID: 0x152D) == "JMicron (0x152D)")
        #expect(db.formatChip(vendorID: 0x174C) == "ASMedia (0x174C)")
        #expect(db.formatChip(vendorID: 0x0BDA) == "Realtek (0x0BDA)")
    }

    @Test func testUnknownBridgeLookup() {
        let db = USBBridgeDatabase.shared

        #expect(db.vendorName(for: 0x9999) == nil)
        #expect(db.vendorName(for: 0x0000) == nil)
        #expect(db.vendorName(for: 0xABCD) == nil)

        let formatted = db.formatChip(vendorID: 0xABCD)
        #expect(formatted.contains("0xABCD"))
    }

    @Test func testDatabaseLoadingFromValidJSON() throws {
        let json = """
        [
            { "vendorId": "0x1234", "vendor": "TestVendor", "notes": "Test chip" },
            { "vendorId": "0x5678", "vendor": "AnotherVendor", "notes": "" }
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let bridges = try USBBridgeDatabase.load(from: data)
        #expect(bridges.count == 2)
        #expect(bridges.first?.vendor == "TestVendor")
        #expect(bridges.first?.numericVendorID == 0x1234)
        #expect(bridges.last?.vendor == "AnotherVendor")
        #expect(bridges.last?.numericVendorID == 0x5678)
    }

    @Test func testDatabaseLoadingMalformedJSONDoesNotCrash() {
        let malformed = "This is not valid JSON at all { [ }".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try USBBridgeDatabase.load(from: malformed)
        }

        let empty = Data()
        #expect(throws: (any Error).self) {
            _ = try USBBridgeDatabase.load(from: empty)
        }
    }

    @Test func testDatabaseLoadingMissingFileDoesNotCrash() {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_usb_bridges_\(UUID().uuidString).json")
        #expect(throws: (any Error).self) {
            _ = try USBBridgeDatabase.load(from: nonExistentURL)
        }
    }

    @Test func testFallbackBridgesAreComplete() {
        let fallbacks = USBBridgeDatabase.fallbackBridges
        #expect(fallbacks.count >= 3)
        let hasJMicron = fallbacks.contains { $0.vendor == "JMicron" && $0.numericVendorID == 0x152D }
        let hasASMedia = fallbacks.contains { $0.vendor == "ASMedia" && $0.numericVendorID == 0x174C }
        let hasRealtek = fallbacks.contains { $0.vendor == "Realtek" && $0.numericVendorID == 0x0BDA }
        #expect(hasJMicron)
        #expect(hasASMedia)
        #expect(hasRealtek)
    }

    @Test func testLinkSpeedFormatting() {
        func makeDisk(bps: UInt64?) -> PhysicalDisk {
            PhysicalDisk(
                bsdName: "disk10",
                model: "USB Drive",
                sizeBytes: 500_000_000_000,
                isInternal: false,
                driveConnection: .usb,
                volumeNames: ["USB"],
                usbVendorID: 0x152D,
                usbProductID: 0x0562,
                usbLinkSpeedBps: bps,
                protocolType: .usb,
                mediumType: .solidState,
                healthCapability: .unsupported(reason: .usbBridge)
            )
        }

        #expect(makeDisk(bps: 40_000_000_000).usbLinkSpeedLabel?.contains("40") == true)
        #expect(makeDisk(bps: 40_000_000_000).usbLinkSpeedLabel?.contains("USB4") == true)

        #expect(makeDisk(bps: 20_000_000_000).usbLinkSpeedLabel?.contains("20") == true)
        #expect(makeDisk(bps: 20_000_000_000).usbLinkSpeedLabel?.contains("USB 3.2 Gen 2x2") == true)

        #expect(makeDisk(bps: 10_000_000_000).usbLinkSpeedLabel?.contains("10") == true)
        #expect(makeDisk(bps: 10_000_000_000).usbLinkSpeedLabel?.contains("USB 3.2 Gen 2") == true)

        #expect(makeDisk(bps: 5_000_000_000).usbLinkSpeedLabel?.contains("5") == true)
        #expect(makeDisk(bps: 5_000_000_000).usbLinkSpeedLabel?.contains("USB 3.0") == true)

        #expect(makeDisk(bps: 480_000_000).usbLinkSpeedLabel?.contains("480") == true)
        #expect(makeDisk(bps: 480_000_000).usbLinkSpeedLabel?.contains("USB 2.0") == true)

        #expect(makeDisk(bps: 12_000_000).usbLinkSpeedLabel?.contains("12") == true)
        #expect(makeDisk(bps: 12_000_000).usbLinkSpeedLabel?.contains("USB 1.1") == true)

        #expect(makeDisk(bps: nil).usbLinkSpeedLabel == nil)
    }

    @Test func testProtocolFormatting() {
        let uasDisk = PhysicalDisk(
            bsdName: "disk11",
            model: "Fast SSD",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            usbIsUAS: true,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        #expect(uasDisk.usbProtocolLabel == "UAS (USB Attached SCSI)")

        let botDisk = PhysicalDisk(
            bsdName: "disk12",
            model: "Slow Flash Drive",
            sizeBytes: 64_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            usbIsUAS: false,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        #expect(botDisk.usbProtocolLabel == "BOT (Bulk-Only Transport)")

        let unknownProtoDisk = PhysicalDisk(
            bsdName: "disk13",
            model: "Generic Drive",
            sizeBytes: 64_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            usbIsUAS: nil,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        #expect(unknownProtoDisk.usbProtocolLabel == nil)
    }

    @Test func testSimulatedFixtures() {
        // 1. Seagate Backup Plus (known JMicron chip, BOT, 5 Gb/s)
        let seagate = PhysicalDisk(
            bsdName: "disk11",
            model: "Seagate Backup Plus",
            sizeBytes: 2_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["Seagate Backup"],
            usbVendorID: 0x152D,
            usbProductID: 0x0562,
            usbVendorName: "JMicron",
            usbProductName: "JMS567",
            usbLinkSpeedBps: 5_000_000_000,
            usbBcdUSB: 0x0300,
            usbIsUAS: false,
            protocolType: .usb,
            mediumType: .rotational,
            healthCapability: .unsupported(reason: .usbBridge),
            smartAvailability: .notSupportedByEnclosure
        )

        #expect(seagate.isExternal)
        #expect(!seagate.isInternal)
        #expect(seagate.usbBridgeLabel == "JMicron (0x152D)")
        #expect(seagate.usbLinkSpeedLabel?.contains("5") == true)
        #expect(seagate.usbProtocolLabel == "BOT (Bulk-Only Transport)")
        #expect(seagate.volumeNames == ["Seagate Backup"])

        // 2. Crucial X8 Portable SSD (known Realtek chip, UAS, 10 Gb/s)
        let crucial = PhysicalDisk(
            bsdName: "disk12",
            model: "Crucial X8 Portable SSD",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: ["Crucial X8"],
            usbVendorID: 0x0BDA,
            usbProductID: 0x9210,
            usbVendorName: "Realtek",
            usbProductName: "RTL9210",
            usbLinkSpeedBps: 10_000_000_000,
            usbBcdUSB: 0x0320,
            usbIsUAS: true,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge),
            smartAvailability: .notSupportedByEnclosure
        )

        #expect(crucial.isExternal)
        #expect(crucial.usbBridgeLabel == "Realtek (0x0BDA)")
        #expect(crucial.usbLinkSpeedLabel?.contains("10") == true)
        #expect(crucial.usbProtocolLabel == "UAS (USB Attached SCSI)")

        // 3. Enclosure with Unknown Chip (0xABCD)
        let unknownEnclosure = PhysicalDisk(
            bsdName: "disk13",
            model: "Unknown Enclosure",
            sizeBytes: 500_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            usbVendorID: 0xABCD,
            usbProductID: 0x1234,
            usbLinkSpeedBps: 5_000_000_000,
            usbIsUAS: true,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )

        #expect(unknownEnclosure.usbBridgeLabel?.contains("0xABCD") == true)

        // 4. Drive with completely missing USB properties
        let bareDisk = PhysicalDisk(
            bsdName: "disk14",
            model: "Bare USB",
            sizeBytes: 128_000_000_000,
            isInternal: false,
            driveConnection: .usb,
            volumeNames: [],
            usbVendorID: nil,
            usbProductID: nil,
            usbLinkSpeedBps: nil,
            usbIsUAS: nil,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )

        #expect(bareDisk.usbBridgeLabel == nil)
        #expect(bareDisk.usbLinkSpeedLabel == nil)
        #expect(bareDisk.usbProtocolLabel == nil)
    }
}
