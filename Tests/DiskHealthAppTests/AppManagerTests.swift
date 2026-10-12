import Testing
import Foundation
@testable import DiskHealthApp
import DiskHealthCore
import BenchmarkCore

@Suite @MainActor struct AppManagerTests {

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

    @Test func unpluggedExternalDriveIsRememberedWithItsLastSeenDate() {
        var tracker = ExternalDiskTracker()
        let internalDisk = makeInternalDisk()
        let external = makeExternalDisk()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        // Initial list: nothing is missing yet.
        #expect(tracker.update(previous: [], current: [internalDisk, external], recordDepartures: false, now: t0).isEmpty)

        // The external drive leaves: remembered under its stable key, with the date.
        let gone = tracker.update(previous: [internalDisk, external], current: [internalDisk], recordDepartures: true, now: t0)
        #expect(gone.map(\.id) == [external.benchmarkKey])
        #expect(gone.first?.lastSeen == t0)
        #expect(external.benchmarkKey == DiskIdentity.key(model: "Crucial X8", serial: "CRUCIAL12345"))

        // An internal drive leaving is not tracked; the external one is still listed.
        let later = t0.addingTimeInterval(60)
        #expect(tracker.update(previous: [internalDisk], current: [], recordDepartures: true, now: later).map(\.id) == [external.benchmarkKey])

        // Plugged back in (under another BSD name): forgotten.
        let back = makeExternalDisk(id: "disk7")
        #expect(tracker.update(previous: [], current: [back], recordDepartures: true, now: later).isEmpty)
    }

    @Test func testStringsLastSeenFormat() {
        let dateStr = "25 sept. 2026 à 10:30"
        let lastSeenText = Strings.lastSeen(date: dateStr)
        #expect(lastSeenText.contains(dateStr))
        #expect(lastSeenText.contains("Vu pour la dernière fois") || lastSeenText.contains("Last seen"))
    }
}
