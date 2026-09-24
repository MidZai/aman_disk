import Testing
import Foundation
@testable import DiskHealthApp
import DiskHealthCore

@Suite final class DiskFilterTests {
    @Test func testDiskFiltering() {
        let internalDisk = PhysicalDisk(bsdName: "disk0", model: "Internal SSD", sizeBytes: 500, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD"], protocolType: .nvme, mediumType: .solidState, healthCapability: .supported, isVirtual: false, isDiskImage: false)
        let virtualDisk = PhysicalDisk(bsdName: "disk1", model: "Virtual Disk", sizeBytes: 100, isInternal: true, connection: .other, volumeNames: ["Virtual Vol"], protocolType: .unknown, mediumType: .unknown, healthCapability: .unsupported(reason: .smartDisabled), isVirtual: true, isDiskImage: false)
        let dmg1 = PhysicalDisk(bsdName: "disk2", model: "Disk Image", sizeBytes: 10, isInternal: true, connection: .other, volumeNames: ["DMG Vol 1"], protocolType: .unknown, mediumType: .unknown, healthCapability: .unsupported(reason: .smartDisabled), isVirtual: false, isDiskImage: true)
        let dmg2 = PhysicalDisk(bsdName: "disk3", model: "Disk Image", sizeBytes: 10, isInternal: true, connection: .other, volumeNames: ["DMG Vol 2"], protocolType: .unknown, mediumType: .unknown, healthCapability: .unsupported(reason: .smartDisabled), isVirtual: false, isDiskImage: true)
        
        let disks = [
            RealDisk(physical: internalDisk, snapshot: nil, health: HealthAssessment(status: .good, healthPercent: 100, reasons: []), lastRead: Date()),
            RealDisk(physical: virtualDisk, snapshot: nil, health: HealthAssessment(status: .unknown, healthPercent: nil, reasons: []), lastRead: Date()),
            RealDisk(physical: dmg1, snapshot: nil, health: HealthAssessment(status: .unknown, healthPercent: nil, reasons: []), lastRead: Date()),
            RealDisk(physical: dmg2, snapshot: nil, health: HealthAssessment(status: .unknown, healthPercent: nil, reasons: []), lastRead: Date())
        ]
        
        let volumes = [
            Volume(bsdName: "disk0s1", name: "Macintosh HD", mountPoint: "/", format: "apfs", totalBytes: 500, availableBytes: 100, physicalDiskBSDNames: ["disk0"]),
            Volume(bsdName: "disk1s1", name: "Virtual Vol", mountPoint: "/Volumes/Virt", format: "apfs", totalBytes: 100, availableBytes: 100, physicalDiskBSDNames: ["disk1"]),
            Volume(bsdName: "disk2s1", name: "DMG Vol 1", mountPoint: "/Volumes/DMG1", format: "hfs", totalBytes: 10, availableBytes: 0, physicalDiskBSDNames: ["disk2"]),
            Volume(bsdName: "disk3s1", name: "DMG Vol 2", mountPoint: "/Volumes/DMG2", format: "hfs", totalBytes: 10, availableBytes: 0, physicalDiskBSDNames: ["disk3"])
        ]
        
        let (filteredDisks, filteredVols) = DiskFilter.filter(disks: disks, volumes: volumes)
        
        #expect(filteredDisks.count == 1)
        #expect(filteredDisks[0].id == "disk0")
        
        #expect(filteredVols.count == 1)
        #expect(filteredVols[0].bsdName == "disk0s1")
    }
}
