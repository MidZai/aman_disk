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
        let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
        // Clear history for demo
        let store = HistoryStore.shared
        // Generating 7-day history
        var current = Date().addingTimeInterval(-7 * 24 * 3600)
        let end = Date()
        
        while current < end {
            let hour = Calendar.current.component(.hour, from: current)
            
            // Coupure d'une nuit il y a 3 jours (entre minuit et 8h)
            let daysAgo = end.timeIntervalSince(current) / (24 * 3600)
            if daysAgo > 2.5 && daysAgo < 3.5 && hour >= 0 && hour < 8 {
                current = current.addingTimeInterval(5 * 60)
                continue
            }
            
            // Temp 26 to 34, slightly higher in afternoon
            var baseTemp = 28.0
            if hour >= 12 && hour <= 18 {
                baseTemp = 32.0
            }
            // Add some deterministic noise
            let noise = Double(Int(current.timeIntervalSince1970) % 5) - 2.0
            let tempC = Int(baseTemp + noise)
            
            let sample = HistorySample(
                date: current,
                temperatureC: tempC,
                percentageUsed: 2,
                dataUnitsWritten: 94_335_937,
                dataUnitsRead: 100_000_000,
                powerOnHours: 1200,
                mediaErrors: 0,
                availableSpare: 100
            )
            store.append(sample, for: key)
            current = current.addingTimeInterval(5 * 60)
        }

        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk2() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk1", model: "APPLE SSD AP0512Z", sizeBytes: 512_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Old)"], usbVendorID: nil, usbProductID: nil)
        let smart = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 305, availableSpare: 100, availableSpareThreshold: 10, percentageUsed: 91, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "DEMO5678", modelNumber: "APPLE SSD AP0512Z", firmwareRevision: "1.0", warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 512_000_000_000)
        let health = HealthEngine.evaluate(smart: smart, identify: identify)
        let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
        // Clear history for demo
        let store = HistoryStore.shared
        // Generating 7-day history
        var current = Date().addingTimeInterval(-7 * 24 * 3600)
        let end = Date()
        
        while current < end {
            let hour = Calendar.current.component(.hour, from: current)
            
            // Coupure d'une nuit il y a 3 jours (entre minuit et 8h)
            let daysAgo = end.timeIntervalSince(current) / (24 * 3600)
            if daysAgo > 2.5 && daysAgo < 3.5 && hour >= 0 && hour < 8 {
                current = current.addingTimeInterval(5 * 60)
                continue
            }
            
            // Temp 26 to 34, slightly higher in afternoon
            var baseTemp = 28.0
            if hour >= 12 && hour <= 18 {
                baseTemp = 32.0
            }
            // Add some deterministic noise
            let noise = Double(Int(current.timeIntervalSince1970) % 5) - 2.0
            let tempC = Int(baseTemp + noise)
            
            let sample = HistorySample(
                date: current,
                temperatureC: tempC,
                percentageUsed: 2,
                dataUnitsWritten: 94_335_937,
                dataUnitsRead: 100_000_000,
                powerOnHours: 1200,
                mediaErrors: 0,
                availableSpare: 100
            )
            store.append(sample, for: key)
            current = current.addingTimeInterval(5 * 60)
        }

        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk3() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk2", model: "APPLE SSD AP1024Z", sizeBytes: 1_000_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Failing)"], usbVendorID: nil, usbProductID: nil)
        let smart = NVMeSmartLog(criticalWarning: 1, compositeTemperatureKelvin: 320, availableSpare: 4, availableSpareThreshold: 10, percentageUsed: 95, dataUnitsRead: 0, dataUnitsWritten: 0, hostReadCommands: 0, hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 0, powerOnHours: 0, unsafeShutdowns: 0, mediaErrors: 14, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: "DEMO9012", modelNumber: "APPLE SSD AP1024Z", firmwareRevision: "1.0", warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 1_000_000_000_000)
        let health = HealthEngine.evaluate(smart: smart, identify: identify)
        let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
        // Clear history for demo
        let store = HistoryStore.shared
        // Generating 7-day history
        var current = Date().addingTimeInterval(-7 * 24 * 3600)
        let end = Date()
        
        while current < end {
            let hour = Calendar.current.component(.hour, from: current)
            
            // Coupure d'une nuit il y a 3 jours (entre minuit et 8h)
            let daysAgo = end.timeIntervalSince(current) / (24 * 3600)
            if daysAgo > 2.5 && daysAgo < 3.5 && hour >= 0 && hour < 8 {
                current = current.addingTimeInterval(5 * 60)
                continue
            }
            
            // Temp 26 to 34, slightly higher in afternoon
            var baseTemp = 28.0
            if hour >= 12 && hour <= 18 {
                baseTemp = 32.0
            }
            // Add some deterministic noise
            let noise = Double(Int(current.timeIntervalSince1970) % 5) - 2.0
            let tempC = Int(baseTemp + noise)
            
            let sample = HistorySample(
                date: current,
                temperatureC: tempC,
                percentageUsed: 2,
                dataUnitsWritten: 94_335_937,
                dataUnitsRead: 100_000_000,
                powerOnHours: 1200,
                mediaErrors: 0,
                availableSpare: 100
            )
            store.append(sample, for: key)
            current = current.addingTimeInterval(5 * 60)
        }

        return DemoDisk(physical: physical, smart: smart, identify: identify, health: health)
    }
    
    private static func makeDisk4() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk3", model: "External SSD", sizeBytes: 1_000_000_000_000, isInternal: false, connection: .usb, volumeNames: ["Sauvegardes"], usbVendorID: 0x0BDA, usbProductID: 0x9210)
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Santé non lisible"])
        return DemoDisk(physical: physical, smart: nil, identify: nil, health: health)
    }
}
