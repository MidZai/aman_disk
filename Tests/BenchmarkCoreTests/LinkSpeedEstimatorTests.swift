import Testing
import Foundation
@testable import BenchmarkCore
import DiskHealthCore

@Suite struct LinkSpeedEstimatorTests {

    @Test func testUSB2Estimates() {
        let physical = PhysicalDisk(
            bsdName: "disk2",
            model: "USB 2.0 Flash Drive",
            sizeBytes: 16_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["USB2"],
            usbLinkSpeedBps: 480_000_000,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate != nil)
        #expect(estimate?.linkSpeedText == "USB 480 Mb/s")
        #expect(estimate?.practicalMaxMBps == 43)
        #expect(estimate?.explanation.contains("43") == true)
    }

    @Test func testUSB3_5GbpsEstimates() {
        let physical = PhysicalDisk(
            bsdName: "disk3",
            model: "Seagate Expansion 5G",
            sizeBytes: 2_000_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Expansion"],
            usbLinkSpeedBps: 5_000_000_000,
            protocolType: .ata,
            mediumType: .rotational,
            healthCapability: .supported
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate != nil)
        #expect(estimate?.linkSpeedText == "USB 5 Gb/s")
        #expect(estimate?.practicalMaxMBps == 450)
        #expect(estimate?.explanation.contains("450") == true)
    }

    @Test func testUSB3_10GbpsEstimates() {
        let physical = PhysicalDisk(
            bsdName: "disk4",
            model: "Crucial X8 10G",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Crucial"],
            usbLinkSpeedBps: 10_000_000_000,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate != nil)
        #expect(estimate?.linkSpeedText == "USB 10 Gb/s")
        #expect(estimate?.practicalMaxMBps == 1050)
    }

    @Test func testUSB3_20GbpsEstimates() {
        let physical = PhysicalDisk(
            bsdName: "disk5",
            model: "Kingston XS2000 20G",
            sizeBytes: 2_000_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Kingston"],
            usbLinkSpeedBps: 20_000_000_000,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate != nil)
        #expect(estimate?.linkSpeedText == "USB 20 Gb/s")
        #expect(estimate?.practicalMaxMBps == 2050)
    }

    @Test func testThunderboltNVMeEstimates() {
        let physical = PhysicalDisk(
            bsdName: "disk6",
            model: "OWC Envoy Pro FX",
            sizeBytes: 1_000_000_000_000,
            isInternal: false,
            connection: .nvmeExternal,
            driveConnection: .thunderboltNVMe,
            volumeNames: ["Envoy"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate != nil)
        #expect(estimate?.linkSpeedText == "Thunderbolt / USB4")
        #expect(estimate?.practicalMaxMBps == 3000)
    }

    @Test func testInternalDriveReturnsNil() {
        let physical = PhysicalDisk(
            bsdName: "disk0",
            model: "APPLE SSD AP0512Z",
            sizeBytes: 500_000_000_000,
            isInternal: true,
            connection: .nvmeInternal,
            volumeNames: ["Macintosh HD"],
            protocolType: .nvme,
            mediumType: .solidState,
            healthCapability: .supported
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate == nil)
    }

    @Test func testExternalUnknownSpeedReturnsNil() {
        let physical = PhysicalDisk(
            bsdName: "disk7",
            model: "Unknown Bridge Enclosure",
            sizeBytes: 500_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["External"],
            usbLinkSpeedBps: nil,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )
        let estimate = LinkSpeedEstimator.estimate(for: physical)
        #expect(estimate == nil)
    }
}
