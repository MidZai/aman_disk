import Foundation
import DiskHealthCore

public enum DemoData {
    public struct DemoDisk {
        let physical: PhysicalDisk
        let smart: NVMeSmartLog?
        let identify: NVMeIdentify?
        let health: HealthAssessment
    }
    
    public static let disks: [DemoDisk] = [
        makeDisk1(),
        makeDisk2(),
        makeDisk3(),
        makeDisk4()
    ]
    
    private static func makeDisk1() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk0", model: "APPLE SSD AP2048Z", sizeBytes: 2_000_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD"], usbVendorID: nil, usbProductID: nil)
        let smart = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 311, availableSpare: 100, availableSpareThreshold: 10, percentageUsed: 2, dataUnitsRead: 100_000_000, dataUnitsWritten: 94_335_937, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "DEMO1234", modelNumber: "APPLE SSD AP2048Z", firmwareRevision: "1.0", warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 2_000_000_000_000)
        let health = HealthEngine.evaluate(smart: smart, identify: identify)
        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk2() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk1", model: "APPLE SSD AP0512Z", sizeBytes: 512_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Old)"], usbVendorID: nil, usbProductID: nil)
        let smart = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 305, availableSpare: 100, availableSpareThreshold: 10, percentageUsed: 91, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "DEMO5678", modelNumber: "APPLE SSD AP0512Z", firmwareRevision: "1.0", warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 512_000_000_000)
        let health = HealthEngine.evaluate(smart: smart, identify: identify)
        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk3() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk2", model: "APPLE SSD AP1024Z", sizeBytes: 1_000_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Failing)"], usbVendorID: nil, usbProductID: nil)
        let smart = NVMeSmartLog(criticalWarning: 1, compositeTemperatureKelvin: 320, availableSpare: 4, availableSpareThreshold: 10, percentageUsed: 95, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 14, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "DEMO9012", modelNumber: "APPLE SSD AP1024Z", firmwareRevision: "1.0", warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 1_000_000_000_000)
        let health = HealthEngine.evaluate(smart: smart, identify: identify)
        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk4() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk3", model: "External SSD", sizeBytes: 1_000_000_000_000, isInternal: false, connection: .usb, volumeNames: ["Sauvegardes"], usbVendorID: 0x0BDA, usbProductID: 0x9210)
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Santé non lisible"])
        return DemoDisk(physical: physical, smart: nil, identify: nil, health: health)
    }
}
