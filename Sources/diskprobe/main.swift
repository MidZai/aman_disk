import Foundation
import DiskHealthCore

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
    } else {
        print("Unknown command: \(command)")
    }
} else {
    print("diskprobe OK")
}
