import Testing
import Foundation
@testable import DiskHealthApp
import DiskHealthCore

/// The NVMe Identify cache is keyed by BSD name, which can be reused by another drive:
/// a plug/unplug event for that name, or a wake from sleep, must invalidate it.
@Suite struct IdentifyCacheTests {
    private func disk(_ bsdName: String, serial: String) -> RealDisk {
        let physical = PhysicalDisk(bsdName: bsdName, model: "Crucial X8", sizeBytes: 1, isInternal: false, connection: .usb,
                                    volumeNames: [], protocolType: .nvme, mediumType: .solidState, healthCapability: .supported)
        let log = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 310, availableSpare: 100, availableSpareThreshold: 10,
                               percentageUsed: 1, dataUnitsRead: 1, dataUnitsWritten: 1, hostReadCommands: 0, hostWriteCommands: 0,
                               controllerBusyTimeMinutes: 0, powerCycles: 1, powerOnHours: 1, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: serial, modelNumber: "Crucial X8", firmwareRevision: "1.0",
                                    warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 1)
        let snapshot = DiskHealthSnapshot.nvme(log, identify)
        return RealDisk(physical: physical, snapshot: snapshot, health: AppManager.evaluate(snapshot))
    }

    @Test func plugEventForANameDropsItsCachedIdentify() {
        var cache = IdentifyCache()
        let disks = [disk("disk4", serial: "AAAA"), disk("disk5", serial: "BBBB")]
        #expect(cache.known(from: disks).keys.sorted() == ["disk4", "disk5"])
        cache.invalidate(bsdName: "disk4")
        let known = cache.known(from: disks)
        #expect(known["disk4"] == nil)
        #expect(known["disk5"]?.serialNumber == "BBBB")
        // Consumed: the next read starts from the fresh list again.
        #expect(cache.known(from: disks)["disk4"]?.serialNumber == "AAAA")
    }

    @Test func wakeFromSleepDropsEveryCachedIdentify() {
        var cache = IdentifyCache()
        cache.invalidateAll()
        #expect(cache.known(from: [disk("disk4", serial: "AAAA")]).isEmpty)
    }
}
