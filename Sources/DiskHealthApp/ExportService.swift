import Foundation
import AppKit
import DiskHealthCore

public struct ExportService {
    
    public static func generateSummary(disk: RealDisk) -> String {
        var lines = [String]()
        lines.append("Rapport Disk Health")
        
        let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
        let sizeStr = String(format: "%.1f Go", sizeGB)
        lines.append("Disque : \(disk.physical.model) (\(sizeStr))")
        
        let serial = disk.identify?.serialNumber ?? "Inconnu"
        lines.append("N° de série : \(serial)")
        
        let statusStr: String
        switch disk.health.status {
        case .good: statusStr = "En bonne santé"
        case .caution: statusStr = "Attention"
        case .bad: statusStr = "Critique"
        case .unknown: statusStr = "Inconnu"
        }
        
        if disk.health.status == .good {
            lines.append("État : \(statusStr)")
        } else {
            let reason = disk.health.reasons.first ?? ""
            lines.append("État : \(statusStr) (\(reason))")
        }
        
        lines.append("")
        
        if let smart = disk.smart {
            let tempC = smart.temperatureCelsius
            lines.append("Température actuelle : \(tempC ?? 0) °C")
            
            let used = smart.percentageUsed
            lines.append("Pourcentage de vie : \(used) % utilisés (\(100 - used) % restants)")
            
            let readTB = Double(smart.dataUnitsRead) * 512_000.0 / 1_000_000_000_000.0
            let writeTB = Double(smart.dataUnitsWritten) * 512_000.0 / 1_000_000_000_000.0
            lines.append(String(format: "Données lues : %.1f To / Écrites : %.1f To", readTB, writeTB))
            
            lines.append("")
            lines.append("S.M.A.R.T. :")
            
            let attrs = NVMeAttributeCatalog.attributes(from: smart, identify: disk.identify)
            for attr in attrs {
                let hexID = "0x" + String(format: "%02X", attr.id)
                lines.append("\(hexID) \(attr.name) : \(attr.rawValue)")
            }
        } else {
            lines.append("Données S.M.A.R.T. indisponibles.")
        }
        
        return lines.joined(separator: "\n")
    }
    
    public static func copySummary(disk: RealDisk) {
        let text = generateSummary(disk: disk)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    public static func exportJSON(disk: RealDisk) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(disk) else { return }
        
        let panel = NSSavePanel()
        panel.title = "Exporter le rapport DiskHealth"
        let safeModel = disk.physical.model.replacingOccurrences(of: " ", with: "_")
        panel.nameFieldStringValue = "DiskHealth_Report_\(safeModel).json"
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
