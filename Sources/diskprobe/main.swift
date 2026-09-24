import Foundation
import DiskHealthCore
import BenchmarkCore

// L'outil en ligne de commande est encore entièrement en français : on y garde les textes du cœur en français.
Localization.language = .french

let args = CommandLine.arguments

func printHexDump(data: Data, limit: Int? = nil) {
    let maxCount = limit ?? data.count
    let chunkCount = min(data.count, maxCount)
    
    for i in stride(from: 0, to: chunkCount, by: 16) {
        let chunk = data[i..<min(i + 16, chunkCount)]
        let hexString = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
        print(String(format: "%04x: %@", i, hexString))
    }
}

if args.count > 1 {
    let command = args[1]
    
    if command == "list" {
        let disks = DiskDiscovery.listPhysicalDisks()
        
        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(disks), let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            print("Found \(disks.count) physical disk(s):")
            for disk in disks {
                let sizeGB = Double(disk.sizeBytes) / 1_000_000_000.0
                let internalStr = disk.isInternal ? "Internal" : "External"
                print(String(format: "%-5@ %-20@ %6.1f GB  %-8@ %-12@", disk.bsdName, disk.model, sizeGB, internalStr, disk.connection.rawValue))
                if !disk.volumeNames.isEmpty {
                    print("  Volumes: \(disk.volumeNames.joined(separator: ", "))")
                }
                if let vid = disk.usbVendorID, let pid = disk.usbProductID {
                    print(String(format: "  USB VID: 0x%04X, PID: 0x%04X", vid, pid))
                }
            }
        }
    } else if command == "detect" {
        let disks = DiskDiscovery.listPhysicalDisks()
        for disk in disks {
            var capabilityStr = ""
            switch disk.healthCapability {
            case .supported:
                capabilityStr = "supported"
            case .unsupported(let reason):
                capabilityStr = "unsupported(\(reason.rawValue))"
            }
            print("\(disk.bsdName) : \(disk.protocolType.rawValue), \(disk.mediumType.rawValue), \(capabilityStr)")
        }
    } else if command == "raw" {
        if args.count < 3 {
            print("Usage: diskprobe raw <bsdName> [--save <folder>]")
            exit(1)
        }
        let bsdName = args[2]
        
        var saveFolder: String? = nil
        if let idx = args.firstIndex(of: "--save"), idx + 1 < args.count {
            saveFolder = args[idx + 1]
        }
        
        do {
            let smartData = try NVMeReader.readSmartLog(bsdName: bsdName)
            print("SMART Data (512 bytes):")
            printHexDump(data: smartData)
            
            let identifyData = try NVMeReader.readIdentify(bsdName: bsdName)
            print("\nIdentify Data (first 256 bytes):")
            printHexDump(data: identifyData, limit: 256)
            
            if let folder = saveFolder {
                let fm = FileManager.default
                if !fm.fileExists(atPath: folder) {
                    try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
                }
                let smartURL = URL(fileURLWithPath: folder).appendingPathComponent("smart.bin")
                let identifyURL = URL(fileURLWithPath: folder).appendingPathComponent("identify.bin")
                
                try smartData.write(to: smartURL)
                try identifyData.write(to: identifyURL)
                print("\nSaved to \(smartURL.path) and \(identifyURL.path)")
            }
        } catch {
            print("Error reading NVMe data: \(error)")
        }
    } else if command == "raw-ata" {
        if args.count < 3 {
            print("Usage: diskprobe raw-ata <bsdName> [--save <folder>]")
            exit(1)
        }
        let bsdName = args[2]
        
        var saveFolder: String? = nil
        if let idx = args.firstIndex(of: "--save"), idx + 1 < args.count {
            saveFolder = args[idx + 1]
        }
        
        do {
            let smartData = try ATAReader.readSmartData(bsdName: bsdName)
            print("ATA SMART Data (512 bytes):")
            printHexDump(data: smartData, limit: 128)
            
            let thresholdsData = try ATAReader.readSmartThresholds(bsdName: bsdName)
            print("\nATA SMART Thresholds (512 bytes):")
            printHexDump(data: thresholdsData, limit: 128)
            
            let identifyData = try ATAReader.readIdentify(bsdName: bsdName)
            print("\nATA Identify Data (512 bytes):")
            printHexDump(data: identifyData, limit: 128)
            
            let status = try ATAReader.readSmartStatus(bsdName: bsdName)
            print("\nATA SMART Status (Threshold Exceeded): \(status)")
            
            if let folder = saveFolder {
                let fm = FileManager.default
                if !fm.fileExists(atPath: folder) {
                    try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
                }
                let smartURL = URL(fileURLWithPath: folder).appendingPathComponent("smart.bin")
                let thresholdsURL = URL(fileURLWithPath: folder).appendingPathComponent("thresholds.bin")
                let identifyURL = URL(fileURLWithPath: folder).appendingPathComponent("identify.bin")
                let statusURL = URL(fileURLWithPath: folder).appendingPathComponent("status.txt")
                
                try smartData.write(to: smartURL)
                try thresholdsData.write(to: thresholdsURL)
                try identifyData.write(to: identifyURL)
                try "\(status)".data(using: .utf8)?.write(to: statusURL)
                
                print("\nSaved to \(folder)")
            }
        } catch {
            print("Error reading ATA data: \(error)")
        }
    } else if command == "smart" {
        if args.count < 3 {
            print("Usage: diskprobe smart <bsdName> [--json]")
            exit(1)
        }
        let bsdName = args[2]
        
        do {
            let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
            
            let snapshot: DiskHealthSnapshot
            if protocolType == .nvme {
                snapshot = try NVMeBackend.read(bsdName: bsdName)
            } else if protocolType == .ata || protocolType == .pcieAhci {
                snapshot = try ATABackend.read(bsdName: bsdName)
            } else {
                print("Error: Unsupported protocol for SMART reading (\(protocolType)).")
                exit(1)
            }
            
            if args.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                
                struct Output: Codable {
                    let snapshot: DiskHealthSnapshot
                    let health: HealthAssessment
                }
                
                let assessment: HealthAssessment
                switch snapshot {
                case .nvme(let smartLog, let identify):
                    assessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
                case .ata(let ataSnapshot):
                    assessment = ATAHealthEvaluator.evaluate(snapshot: ataSnapshot)
                }
                
                let out = Output(snapshot: snapshot, health: assessment)
                if let data = try? encoder.encode(out), let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            } else {
                switch snapshot {
                case .nvme(let smartLog, let identify):
                    let assessment = HealthEngine.evaluate(smart: smartLog, identify: identify)
                    print("Model: \(identify.modelNumber)")
                    print("Serial: \(identify.serialNumber)")
                    print("Health: \(assessment.status.rawValue.uppercased()) (\(assessment.healthPercent.map { "\($0)%" } ?? "Unknown"))")
                    for reason in assessment.reasons {
                        print("- \(reason)")
                    }
                    print("Temperature: \(smartLog.temperatureCelsius.map { "\($0) °C" } ?? "Unknown")")
                    print("Data Written: \(Formatters.dataUnitsToBytesText(smartLog.dataUnitsWritten))")
                case .ata(let ataSnapshot):
                    let assessment = ATAHealthEvaluator.evaluate(snapshot: ataSnapshot)
                    print("Model: \(ataSnapshot.model)")
                    print("Serial: \(ataSnapshot.serialNumber)")
                    print("Health: \(assessment.status.rawValue.uppercased()) (\(assessment.healthPercent.map { "\($0)%" } ?? "Unknown"))")
                    for reason in assessment.reasons {
                        print("- \(reason)")
                    }
                    let profile = ATACatalog.profile(for: ataSnapshot.model)
                    if let tempAttr = ataSnapshot.attributes.first(where: { ATACatalog.attributeInfo(id: $0.id, profile: profile).role == .temperature }) {
                        if let temp = tempAttr.value(for: .temperature) {
                            print("Temperature: \(temp) °C")
                        } else {
                            print("Temperature: Unknown")
                        }
                    } else {
                        print("Temperature: Unknown")
                    }
                }
            }
        } catch {
            print("Error reading SMART data: \(error)")
        }
    } else if command == "volumes" {
        let volumes = VolumeDiscovery.listVolumes()
        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(volumes), let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            print("Found \(volumes.count) volume(s):")
            for vol in volumes {
                let sizeGB = Double(vol.totalBytes) / 1_000_000_000.0
                let phys = vol.physicalDiskBSDNames.isEmpty ? "None" : vol.physicalDiskBSDNames.joined(separator: ", ")
                print(String(format: "%-8@ %-20@ %6.1f GB  %-8@ %-30@ (Phys: %@)", vol.bsdName, vol.name, sizeGB, vol.format, vol.mountPoint, phys))
            }
        }
        } else if command == "bench" {
        BenchCLI.run(args: Array(args.dropFirst(2)))
    } else {        print("Unknown command: \(command)")
    }
} else {
    print("diskprobe OK")
}
