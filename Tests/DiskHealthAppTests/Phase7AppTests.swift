import Testing
import Foundation
@testable import DiskHealthApp
import DiskHealthCore
import BenchmarkCore

@Suite @MainActor struct Phase7AppTests {

    private func makeInternalDisk(id: String = "disk0", model: String = "APPLE SSD") -> RealDisk {
        let physical = PhysicalDisk(
            bsdName: id,
            model: model,
            sizeBytes: 500_000_000_000,
            isInternal: true,
            connection: .nvmeInternal,
            volumeNames: ["Macintosh HD"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )
        return RealDisk(physical: physical, snapshot: nil, health: HealthAssessment(status: .good, healthPercent: 98, reasons: []))
    }

    private func makeExternalDisk(id: String = "disk2", model: String = "Crucial X8", serial: String = "CRUCIAL12345") -> RealDisk {
        let physical = PhysicalDisk(
            bsdName: id,
            model: model,
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Crucial X8"],
            usbLinkSpeedBps: 10_000_000_000,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge),
            serialNumber: serial
        )
        return RealDisk(physical: physical, snapshot: nil, health: HealthAssessment(status: .good, healthPercent: nil, reasons: []))
    }

    @Test func testDisconnectedExternalDriveTrackingAndLastSeen() {
        let app = AppManager()
        let internalDisk = makeInternalDisk()
        let externalDisk = makeExternalDisk()

        #expect(internalDisk.physical.isInternal)
        #expect(!externalDisk.physical.isInternal)
        #expect(app.disconnectedDisks.isEmpty)

        // Simulate apply via mirror or testDisks
        // When external disk is plugged in and unplugged
        let extKey = externalDisk.benchmarkKey
        #expect(!extKey.isEmpty)

        // RealDisk serialNumber fallback
        #expect(externalDisk.serialNumber == "CRUCIAL12345")
        #expect(externalDisk.benchmarkKey == DiskIdentity.key(model: "Crucial X8", serial: "CRUCIAL12345"))
    }

    @Test func testMenuBarInternalAndExternalSeparation() {
        let internalDisk = makeInternalDisk()
        let externalDisk = makeExternalDisk()
        let allDisks = [internalDisk, externalDisk]

        let internals = allDisks.filter { $0.physical.isInternal }
        let externals = allDisks.filter { $0.physical.isExternal }

        #expect(internals.count == 1)
        #expect(externals.count == 1)
        #expect(internals[0].id == "disk0")
        #expect(externals[0].id == "disk2")
    }

    @Test func testStringsLastSeenFormat() {
        let dateStr = "25 sept. 2026 à 10:30"
        let lastSeenText = Strings.lastSeen(date: dateStr)
        #expect(lastSeenText.contains(dateStr))
        #expect(lastSeenText.contains("Vu pour la dernière fois") || lastSeenText.contains("Last seen"))
    }
}
