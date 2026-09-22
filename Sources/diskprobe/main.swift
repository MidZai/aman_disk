import Foundation
import DiskHealthCore

let args = CommandLine.arguments

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
                print(String(format: "%-10@ %-30@ %6.1f GB  %-8@ %-12@", disk.bsdName, disk.model, sizeGB, internalStr, disk.connection.rawValue))
                if !disk.volumeNames.isEmpty {
                    print("  Volumes: \(disk.volumeNames.joined(separator: ", "))")
                }
                if let vid = disk.usbVendorID, let pid = disk.usbProductID {
                    print(String(format: "  USB VID: 0x%04X, PID: 0x%04X", vid, pid))
                }
            }
        }
    } else {
        print("Unknown command: \(command)")
    }
} else {
    print("diskprobe OK")
}
