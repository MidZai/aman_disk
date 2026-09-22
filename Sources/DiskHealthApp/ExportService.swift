import Foundation
import AppKit
import DiskHealthCore
import SwiftUI
import UniformTypeIdentifiers

public struct ExportService {
    
    public static func generateSummary(disk: RealDisk) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        
        var lines = [String]()
        lines.append("Disk Health — Résumé")
        
        let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
        let sizeStr = String(format: "%.1f Go", sizeGB).replacingOccurrences(of: ".", with: ",")
        let loc = disk.physical.isInternal ? "interne" : "externe"
        lines.append("\(disk.physical.model) (\(sizeStr), \(disk.physical.connection.rawValue), \(loc))")
        
        let statusStr: String
        switch disk.health.status {
        case .good: statusStr = "En bonne santé"
        case .caution: statusStr = "À surveiller"
        case .bad: statusStr = "Défaillance probable"
        case .unknown: statusStr = "Santé inconnue"
        }
        
        let reason = disk.health.reasons.first ?? "Aucune anomalie détectée."
        lines.append("État : \(statusStr) — \(reason)")
        
        if let smart = disk.smart {
            lines.append("Température : \(smart.temperatureCelsius ?? 0) °C · Endurance utilisée : \(smart.percentageUsed) % · Réserve : \(smart.availableSpare) %")
            
            let writeTB = Double(smart.dataUnitsWritten) * 512_000.0 / 1_000_000_000_000.0
            let writeStr = String(format: "%.1f To", writeTB).replacingOccurrences(of: ".", with: ",")
            lines.append("Données écrites : \(writeStr) · Heures : \(smart.powerOnHours) h · Cycles : \(smart.powerCycles)")
            
            lines.append("Arrêts non propres : \(smart.unsafeShutdowns) · Erreurs média : \(smart.mediaErrors)")
        }
        
        lines.append("Relevé le \(formatter.string(from: disk.lastRead))")
        return lines.joined(separator: "\n")
    }
    
    public static func copySummary(disk: RealDisk) {
        let text = generateSummary(disk: disk)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private static func getSaveURL(disk: RealDisk, extension ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exporter le rapport Disk Health"
        let safeModel = disk.physical.model.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = formatter.string(from: Date())
        
        panel.nameFieldStringValue = "Rapport-sante-disque_\(safeModel)_\(dateStr).\(ext)"
        
        if let uti = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [uti]
        }
        
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    @MainActor
    public static func exportJSON(disk: RealDisk, includeSerial: Bool = false, includeHistory: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // Let's modify the disk temporarily to hide the serial if needed.
        var exportDisk = disk
        if !includeSerial, let iden = disk.identify {
            let modifiedIdentify = NVMeIdentify(
                serialNumber: "<masqué>",
                modelNumber: iden.modelNumber,
                firmwareRevision: iden.firmwareRevision,
                warningTempKelvin: iden.warningTempKelvin,
                criticalTempKelvin: iden.criticalTempKelvin,
                totalCapacityBytes: iden.totalCapacityBytes
            )
            exportDisk = RealDisk(physical: disk.physical, smart: disk.smart, identify: modifiedIdentify, health: disk.health, lastRead: disk.lastRead)
        }
        
        guard let data = try? encoder.encode(exportDisk) else { return }
        if let url = getSaveURL(disk: disk, extension: "json") {
            do {
                try data.write(to: url)
                ToastCenter.shared.show(message: "Rapport exporté", systemImage: "checkmark.circle")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                ToastCenter.shared.show(message: "L'export a échoué: \(error.localizedDescription)", systemImage: "xmark.octagon")
            }
        }
    }
    
    @MainActor
    public static func exportPDF(disk: RealDisk, includeSerial: Bool = false, includeHistory: Bool = true) {
        guard let url = getSaveURL(disk: disk, extension: "pdf") else { return }
        
        var exportDisk = disk
        if !includeSerial, let iden = disk.identify {
            let modifiedIdentify = NVMeIdentify(
                serialNumber: "Masqué",
                modelNumber: iden.modelNumber,
                firmwareRevision: iden.firmwareRevision,
                warningTempKelvin: iden.warningTempKelvin,
                criticalTempKelvin: iden.criticalTempKelvin,
                totalCapacityBytes: iden.totalCapacityBytes
            )
            exportDisk = RealDisk(physical: disk.physical, smart: disk.smart, identify: modifiedIdentify, health: disk.health, lastRead: disk.lastRead)
        }
        
        let safeModel = disk.physical.model.replacingOccurrences(of: " ", with: "-")
        let title = "Rapport de santé du disque – \(safeModel)" as CFString
        let creator = "Disk Health 0.2.0" as CFString
        let auxInfo = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: creator
        ] as CFDictionary
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: nil, auxInfo) else {
            ToastCenter.shared.show(message: "L'export a échoué", systemImage: "xmark.octagon")
            return
        }
        
        let renderer1 = ImageRenderer(content: ReportPageView(disk: exportDisk, pageNumber: 1, includeHistory: includeHistory))
        let renderer2 = ImageRenderer(content: ReportPageView(disk: exportDisk, pageNumber: 2, includeHistory: includeHistory))
        
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        pdfContext.beginPage(mediaBox: &mediaBox)
        renderer1.render { size, context in
            context(pdfContext)
        }
        pdfContext.endPage()
        
        if includeHistory || disk.smart != nil {
            pdfContext.beginPage(mediaBox: &mediaBox)
            renderer2.render { size, context in
                context(pdfContext)
            }
            pdfContext.endPage()
        }
        
        pdfContext.closePDF()
        
        ToastCenter.shared.show(message: "Rapport exporté", systemImage: "checkmark.circle")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    @MainActor
    public static func exportText(disk: RealDisk, includeSerial: Bool = false, includeHistory: Bool = true) {
        guard let url = getSaveURL(disk: disk, extension: "txt") else { return }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        
        var lines = [String]()
        lines.append("========================================================================")
        lines.append("  RAPPORT DE SANTÉ DU DISQUE")
        lines.append("  Disk Health 0.2.0")
        lines.append("========================================================================")
        
        let idStr = String(format: "DH-%04X", arc4random_uniform(0xFFFF))
        let dFormatter = DateFormatter()
        dFormatter.dateFormat = "yyyyMMdd-HHmm"
        let fullId = "DH-\(dFormatter.string(from: Date()))-\(idStr.components(separatedBy: "-")[1])"
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        var hwModel = "Mac"
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            hwModel = String(cString: model)
        }
        
        lines.append(padRight("  Date du rapport", 22) + formatter.string(from: Date()))
        lines.append(padRight("  Identifiant", 22) + fullId)
        lines.append(padRight("  Mac", 22) + "\(hwModel) — macOS \(osVersion)")
        
        lines.append("------------------------------------------------------------------------")
        lines.append("  VERDICT")
        lines.append("------------------------------------------------------------------------")
        
        let statusStr: String
        switch disk.health.status {
        case .good: statusStr = "En bonne santé"
        case .caution: statusStr = "À surveiller"
        case .bad: statusStr = "Défaillance probable"
        case .unknown: statusStr = "Santé inconnue"
        }
        
        lines.append(padRight("  État", 22) + statusStr)
        let reason = disk.health.reasons.first ?? "Aucune anomalie détectée."
        lines.append(padRight("  Résumé", 22) + reason)
        lines.append("")
        
        lines.append("------------------------------------------------------------------------")
        lines.append("  1. IDENTIFICATION")
        lines.append("------------------------------------------------------------------------")
        lines.append(padRight("  Modèle", 22) + disk.physical.model)
        
        let serial = includeSerial ? (disk.identify?.serialNumber ?? "Inconnu") : "Masqué"
        lines.append(padRight("  Numéro de série", 22) + serial)
        lines.append(padRight("  Firmware", 22) + (disk.identify?.firmwareRevision ?? "Inconnu"))
        let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
        let sizeStr = String(format: "%.1f Go", sizeGB).replacingOccurrences(of: ".", with: ",")
        lines.append(padRight("  Capacité", 22) + sizeStr)
        lines.append(padRight("  Interface", 22) + disk.physical.connection.rawValue)
        let loc = disk.physical.isInternal ? "Interne" : "Externe"
        lines.append(padRight("  Emplacement", 22) + "\(loc) (\(disk.physical.bsdName))")
        lines.append("")
        
        lines.append("------------------------------------------------------------------------")
        lines.append("  2. INDICATEURS CLÉS")
        lines.append("------------------------------------------------------------------------")
        if let smart = disk.smart {
            lines.append(padRight("  Température", 22) + "\(smart.temperatureCelsius ?? 0) °C")
            lines.append(padRight("  Endurance utilisée", 22) + "\(smart.percentageUsed) %")
            lines.append(padRight("  Réserve disponible", 22) + "\(smart.availableSpare) %")
        }
        lines.append("")
        
        lines.append("------------------------------------------------------------------------")
        lines.append("  4. DÉTAIL NVMe SMART / HEALTH")
        lines.append("------------------------------------------------------------------------")
        
        let showRaw = UserDefaults.standard.bool(forKey: "showRawValues")
        
        if showRaw {
            lines.append("  ID    Attribut                        Valeur          Brute     État")
            lines.append("  ----  ------------------------------  --------------  --------  ----------")
        } else {
            lines.append("  ID    Attribut                        Valeur          État")
            lines.append("  ----  ------------------------------  --------------  ----------")
        }
        
        if let smart = disk.smart {
            let attrs = NVMeAttributeCatalog.attributes(from: smart, identify: disk.identify)
            for attr in attrs {
                let idHex = String(format: "0x%02X", attr.id)
                let name = attr.name.count > 30 ? String(attr.name.prefix(27)) + "..." : attr.name
                let val = attr.displayValue.count > 14 ? String(attr.displayValue.prefix(11)) + "..." : attr.displayValue
                let raw = attr.rawValue.count > 8 ? String(attr.rawValue.prefix(5)) + "..." : attr.rawValue
                
                let stateStr = attr.state == .normal ? "Normal" : (attr.state == .warning ? "Attention" : (attr.state == .critical ? "Critique" : "—"))
                
                if showRaw {
                    lines.append("  \(padRight(idHex, 4))  \(padRight(name, 30))  \(padRight(val, 14))  \(padRight(raw, 8))  \(stateStr)")
                } else {
                    lines.append("  \(padRight(idHex, 4))  \(padRight(name, 30))  \(padRight(val, 14))  \(stateStr)")
                }
            }
        }
        
        lines.append("------------------------------------------------------------------------")
        lines.append("  Méthode et limites")
        lines.append("  L'état de santé est calculé à partir des données déclarées par le")
        lines.append("  contrôleur du disque (journal NVMe SMART / Health Information) au")
        lines.append("  moment de la lecture. Il reflète l'usure et les erreurs connues")
        lines.append("  du disque, mais ne peut pas garantir l'absence de panne future.")
        lines.append("  Sauvegardez régulièrement vos données.")
        lines.append("========================================================================")
        
        let text = lines.joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            ToastCenter.shared.show(message: "Rapport exporté", systemImage: "checkmark.circle")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            ToastCenter.shared.show(message: "L'export a échoué", systemImage: "xmark.octagon")
        }
    }
    
    private static func padRight(_ str: String, _ length: Int) -> String {
        if str.count >= length { return str }
        return str + String(repeating: " ", count: length - str.count)
    }
}
