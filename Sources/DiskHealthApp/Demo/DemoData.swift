import Foundation
import DiskHealthCore

public enum DemoData {
    public struct DemoDisk {
        let physical: PhysicalDisk
        let snapshot: DiskHealthSnapshot?
        
        let health: HealthAssessment
    }
    
    public static let disks: [DemoDisk] = [
        makeDisk1(),
        makeDisk2(),
        makeDisk3(),
        makeDisk5(),
        makeDisk6(),
        makeDisk4(),
        makeDiskSD(),
        makeDiskSmartDisabled(),
        makeDiskVirtual(),
        makeDiskNoSmart()
    ]
    
    public static let volumes: [Volume] = [
        Volume(bsdName: "disk1s1", name: "Macintosh HD", mountPoint: "/", format: "APFS", totalBytes: 2_000_000_000_000, availableBytes: 1_200_000_000_000, physicalDiskBSDNames: ["disk0"]),
        Volume(bsdName: "disk2s1", name: "Fusion HD", mountPoint: "/Volumes/Fusion HD", format: "APFS", totalBytes: 1_500_000_000_000, availableBytes: 900_000_000_000, physicalDiskBSDNames: ["disk4", "disk5"]),
        Volume(bsdName: "disk3s1", name: "Sauvegardes", mountPoint: "/Volumes/Sauvegardes", format: "ExFAT", totalBytes: 1_000_000_000_000, availableBytes: 400_000_000_000, physicalDiskBSDNames: ["disk3"])
    ]
    
    private static func makeDisk1() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk0", model: "APPLE SSD AP2048Z", sizeBytes: 2_000_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD"], usbVendorID: nil, usbProductID: nil, protocolType: .nvme, mediumType: .solidState, healthCapability: .supported)
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

        return DemoDisk(physical: physical, snapshot: .nvme(smart, identify), health: health)
    }
    
    private static func makeDisk2() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk1", model: "APPLE SSD AP0512Z", sizeBytes: 512_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Old)"], usbVendorID: nil, usbProductID: nil, protocolType: .nvme, mediumType: .solidState, healthCapability: .supported)
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
            
            var baseTemp = 30.0
            if hour >= 12 && hour <= 18 {
                baseTemp = 35.0
            }
            let noise = Double(Int(current.timeIntervalSince1970) % 5) - 2.0
            let tempC = Int(baseTemp + noise)
            
            let sample = HistorySample(
                date: current,
                temperatureC: tempC,
                percentageUsed: 91,
                dataUnitsWritten: 800_000_000,
                dataUnitsRead: 750_000_000,
                powerOnHours: 14000,
                mediaErrors: 0,
                availableSpare: 100
            )
            store.append(sample, for: key)
            current = current.addingTimeInterval(5 * 60)
        }

        return DemoDisk(physical: physical, snapshot: .nvme(smart, identify), health: health)
    }
    
    private static func makeDisk3() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk2", model: "APPLE SSD AP1024Z", sizeBytes: 1_000_000_000_000, isInternal: true, connection: .nvmeInternal, volumeNames: ["Macintosh HD (Failing)"], usbVendorID: nil, usbProductID: nil, protocolType: .nvme, mediumType: .solidState, healthCapability: .supported)
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
            
            var baseTemp = 42.0
            if hour >= 12 && hour <= 18 {
                baseTemp = 50.0
            }
            let noise = Double(Int(current.timeIntervalSince1970) % 5) - 2.0
            let tempC = Int(baseTemp + noise)
            
            let sample = HistorySample(
                date: current,
                temperatureC: tempC,
                percentageUsed: 95,
                dataUnitsWritten: 1_200_000_000,
                dataUnitsRead: 1_100_000_000,
                powerOnHours: 25000,
                mediaErrors: 14,
                availableSpare: 4
            )
            store.append(sample, for: key)
            current = current.addingTimeInterval(5 * 60)
        }

        return DemoDisk(physical: physical, snapshot: .nvme(smart, identify), health: health)
    }
    
    
    private static func makeATASmartData(attributes: [(id: UInt8, flags: UInt16, current: UInt8, worst: UInt8, raw: [UInt8])]) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        for (i, attr) in attributes.enumerated() {
            if i >= 30 { break }
            let offset = 2 + (i * 12)
            data[offset] = attr.id
            data[offset+1] = UInt8(attr.flags & 0xFF)
            data[offset+2] = UInt8((attr.flags >> 8) & 0xFF)
            data[offset+3] = attr.current
            data[offset+4] = attr.worst
            for j in 0..<min(6, attr.raw.count) {
                data[offset+5+j] = attr.raw[j]
            }
        }
        let sum = data.prefix(511).reduce(0) { (UInt16($0) + UInt16($1)) % 256 }
        let checksum = (256 - sum) % 256
        data[511] = UInt8(checksum)
        return Data(data)
    }

    private static func makeATAThresholds(thresholds: [(id: UInt8, threshold: UInt8)]) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        for (i, t) in thresholds.enumerated() {
            if i >= 30 { break }
            let offset = 2 + (i * 12)
            data[offset] = t.id
            data[offset+1] = t.threshold
        }
        let sum = data.prefix(511).reduce(0) { (UInt16($0) + UInt16($1)) % 256 }
        let checksum = (256 - sum) % 256
        data[511] = UInt8(checksum)
        return Data(data)
    }

    private static func makeATAIdentify(model: String, rotationRate: Int) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        func writeString(_ str: String, offset: Int, length: Int) {
            let padded = str.padding(toLength: length, withPad: " ", startingAt: 0)
            let bytes = Array(padded.utf8)
            for i in 0..<(length/2) {
                let b1 = i*2 < bytes.count ? bytes[i*2] : 32
                let b2 = i*2+1 < bytes.count ? bytes[i*2+1] : 32
                data[offset + i*2] = b2
                data[offset + i*2 + 1] = b1
            }
        }
        writeString(model, offset: 54, length: 40)
        data[434] = UInt8(rotationRate & 0xFF)
        data[435] = UInt8((rotationRate >> 8) & 0xFF)
        return Data(data)
    }

    private static func makeDisk5() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk4", model: "APPLE SSD SM0512G", sizeBytes: 500_277_790_720, isInternal: true, connection: .sata, volumeNames: ["Macintosh HD"], usbVendorID: nil, usbProductID: nil, protocolType: .pcieAhci, mediumType: .solidState, healthCapability: .supported)
        
        let smartData = makeATASmartData(attributes: [
            (1, 0, 200, 200, [0, 0, 0, 0, 0, 0]),
            (5, 0, 100, 100, [0, 0, 0, 0, 0, 0]),
            (9, 0, 93, 93, [59, 123, 0, 0, 0, 0]), // 31483 hours
            (12, 0, 40, 40, [32, 234, 0, 0, 0, 0]), // 59936 cycles
            (173, 0, 183, 183, [0, 0, 0, 0, 0, 0]), // Wear leveling count 183 -> 17% used
            (174, 0, 99, 99, [52, 105, 105, 6, 0, 0]), // Reads
            (175, 0, 99, 99, [24, 60, 215, 6, 0, 0]), // Writes
            (192, 0, 99, 99, [10, 2, 0, 0, 0, 0]), // Unsafe shutdowns
            (194, 0, 60, 35, [40, 0, 0, 0, 0, 0]), // Temp 40C
            (197, 0, 100, 100, [0, 0, 0, 0, 0, 0])
        ])
        
        let thresholdsData = makeATAThresholds(thresholds: [
            (1, 0), (5, 0), (9, 0), (12, 0), (173, 100), (194, 0), (197, 0)
        ])
        
        let identifyData = makeATAIdentify(model: "APPLE SSD SM0512G", rotationRate: 1)
        
        let parsedSmart = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: false)
        let health = ATAHealthEvaluator.evaluate(snapshot: parsedSmart!)
        
        return DemoDisk(physical: physical, snapshot: .ata(parsedSmart!), health: health)
    }

    private static func makeDisk6() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk5", model: "WDC WD10EZEX-00BN5A0", sizeBytes: 1_000_204_886_016, isInternal: true, connection: .sata, volumeNames: ["Data"], usbVendorID: nil, usbProductID: nil, protocolType: .ata, mediumType: .rotational, healthCapability: .supported)
        
        let smartData = makeATASmartData(attributes: [
            (1, 0, 200, 200, [0, 0, 0, 0, 0, 0]),
            (3, 0, 140, 140, [21, 0, 0, 0, 0, 0]),
            (4, 0, 100, 100, [45, 0, 0, 0, 0, 0]),
            (5, 0, 200, 200, [0, 0, 0, 0, 0, 0]),
            (9, 0, 85, 85, [140, 45, 0, 0, 0, 0]), // ~11660 hours
            (12, 0, 100, 100, [42, 0, 0, 0, 0, 0]),
            (192, 0, 200, 200, [15, 0, 0, 0, 0, 0]),
            (194, 0, 110, 95, [38, 0, 0, 0, 0, 0]), // 38C
            (197, 0, 200, 200, [8, 0, 0, 0, 0, 0]), // 8 pending sectors (caution)
            (199, 0, 200, 200, [0, 0, 0, 0, 0, 0])
        ])
        
        let thresholdsData = makeATAThresholds(thresholds: [
            (1, 51), (3, 21), (4, 0), (5, 140), (9, 0), (12, 0), (194, 0), (197, 0)
        ])
        
        let identifyData = makeATAIdentify(model: "WDC WD10EZEX-00BN5A0", rotationRate: 7200)
        
        let parsedSmart = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: false)
        let health = ATAHealthEvaluator.evaluate(snapshot: parsedSmart!)
        
        return DemoDisk(physical: physical, snapshot: .ata(parsedSmart!), health: health)
    }

    private static func makeDisk4() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk3", model: "External SSD", sizeBytes: 1_000_000_000_000, isInternal: false, connection: .usb, volumeNames: ["Sauvegardes"], usbVendorID: 0x0BDA, usbProductID: 0x9210, protocolType: .usb, mediumType: .solidState, healthCapability: .unsupported(reason: .usbBridge))
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [L("Health unreadable", "Santé non lisible")])
        return DemoDisk(physical: physical, snapshot: nil, health: health)
    }

    private static func makeDiskSD() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk6", model: "Apple SD Card Reader", sizeBytes: 64_000_000_000, isInternal: true, connection: .other, volumeNames: ["SD_CARD"], usbVendorID: nil, usbProductID: nil, protocolType: .sdCard, mediumType: .solidState, healthCapability: .unsupported(reason: .sdCardReader))
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [Strings.sdCardReaderText])
        return DemoDisk(physical: physical, snapshot: nil, health: health)
    }

    private static func makeDiskSmartDisabled() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk7", model: "ST3500418AS (SMART Désactivé)", sizeBytes: 500_000_000_000, isInternal: true, connection: .sata, volumeNames: ["OldData"], usbVendorID: nil, usbProductID: nil, protocolType: .ata, mediumType: .rotational, healthCapability: .unsupported(reason: .smartDisabled))
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [Strings.smartDisabledText])
        return DemoDisk(physical: physical, snapshot: nil, health: health)
    }

    private static func makeDiskVirtual() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk8", model: "VMware Virtual SATA Disk", sizeBytes: 120_000_000_000, isInternal: true, connection: .sata, volumeNames: ["VM_Disk"], usbVendorID: nil, usbProductID: nil, protocolType: .virtualDisk, mediumType: .solidState, healthCapability: .unsupported(reason: .virtualDisk))
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [Strings.virtualDiskText])
        return DemoDisk(physical: physical, snapshot: nil, health: health)
    }

    private static func makeDiskNoSmart() -> DemoDisk {
        let physical = PhysicalDisk(bsdName: "disk9", model: "Generic Storage Device", sizeBytes: 250_000_000_000, isInternal: true, connection: .other, volumeNames: ["UnknownMedia"], usbVendorID: nil, usbProductID: nil, protocolType: .unknown, mediumType: .unknown, healthCapability: .unsupported(reason: .noSmartInterface))
        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [Strings.noSmartInterfaceText])
        return DemoDisk(physical: physical, snapshot: nil, health: health)
    }
}
