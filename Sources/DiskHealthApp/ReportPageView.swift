import SwiftUI
import DiskHealthCore

struct ReportPageView: View {
    let disk: RealDisk
    let pageNumber: Int
    let includeHistory: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DiskHealth")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#1D1D1F"))
                    Text("Rapport d'état de santé")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6E6E73"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatter.string(from: Date()))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6E6E73"))
                    Text("Page \(pageNumber)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6E6E73"))
                }
            }
            .padding(.bottom, 16)
            
            Divider()
                .background(Color(hex: "#E5E5EA"))
                .padding(.bottom, 20)
            
            if pageNumber == 1 {
                page1Content
            } else {
                page2Content
            }
            
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: 595, height: 842) // A4 format
        .background(Color.white)
    }
    
    @ViewBuilder
    private var page1Content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Résumé")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1D1D1F"))
            
            Text(disk.physical.model)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#6E6E73"))
            
            // Verdict
            HStack(spacing: 0) {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusString)
                        .font(.system(size: 16, weight: .semibold))
                    Text(disk.health.reasons.first ?? "Aucune anomalie détectée.")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer()
            }
            .background(statusColor.opacity(0.08))
            .cornerRadius(10)
            .padding(.bottom, 8)
            
            sectionHeader("1. Identification")
            
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow("Modèle", disk.physical.model)
                    let serial = disk.identify?.serialNumber ?? (disk.snapshot != nil ? { if case .ata(let s) = disk.snapshot! { return s.serialNumber } else { return nil } }() : nil)
                    infoRow("Numéro de série", serial ?? "Inconnu")
                    let fw = disk.identify?.firmwareRevision ?? (disk.snapshot != nil ? { if case .ata(let s) = disk.snapshot! { return s.firmwareRevision } else { return nil } }() : nil)
                    infoRow("Firmware", fw ?? "Inconnu")
                }
                VStack(alignment: .leading, spacing: 6) {
                    let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
                    infoRow("Capacité", String(format: "%.1f Go", sizeGB))
                    infoRow("Interface", disk.physical.connection.rawValue)
                    infoRow("Emplacement", disk.physical.isInternal ? "Interne" : "Externe")
                }
            }
            .padding(.bottom, 12)
            
            sectionHeader("2. Indicateurs clés")
            if let snap = disk.snapshot {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 6) {
                        switch snap {
                        case .nvme(let smart, _):
                            infoRow("Température", "\(smart.temperatureCelsius ?? 0) °C")
                            infoRow("Endurance utilisée", "\(smart.percentageUsed) %")
                            infoRow("Réserve disponible", "\(smart.availableSpare) %")
                        case .ata(let ataSnap):
                            let profile = ATACatalog.profile(for: ataSnap.model)
                            var tempStr = "—"
                            var usedStr = "—"
                            for attr in ataSnap.attributes {
                                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                                if info.role == .temperature, let t = attr.value(for: .temperature) { tempStr = "\(t) °C" }
                                if info.role == .lifeRemainingPercentNormalized { usedStr = "\(100 - attr.current) %" }
                            }
                            infoRow("Température", tempStr)
                            infoRow("Endurance utilisée", usedStr)
                            infoRow("Réserve disponible", "—")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        switch snap {
                        case .nvme(let smart, _):
                            let readTB = Double(smart.dataUnitsRead) * 512_000.0 / 1_000_000_000_000.0
                            let writeTB = Double(smart.dataUnitsWritten) * 512_000.0 / 1_000_000_000_000.0
                            infoRow("Données lues", String(format: "%.1f To", readTB))
                            infoRow("Données écrites", String(format: "%.1f To", writeTB))
                        case .ata(let ataSnap):
                            let profile = ATACatalog.profile(for: ataSnap.model)
                            var readStr = "—"
                            var writeStr = "—"
                            for attr in ataSnap.attributes {
                                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                                if case .hostReadsBytes(let mult) = info.role {
                                    let readTB = Double(attr.rawValue * mult) / 1_000_000_000_000.0
                                    readStr = String(format: "%.1f To", readTB)
                                }
                                if case .hostWritesBytes(let mult) = info.role {
                                    let writeTB = Double(attr.rawValue * mult) / 1_000_000_000_000.0
                                    writeStr = String(format: "%.1f To", writeTB)
                                }
                            }
                            infoRow("Données lues", readStr)
                            infoRow("Données écrites", writeStr)
                        }
                    }
                }
            }
            
            if !includeHistory {
                Spacer().frame(height: 20)
                smartTable
            }
        }
    }
    
    @ViewBuilder
    private var page2Content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if includeHistory {
                smartTable
            }
            
            Spacer().frame(height: 20)
            
            Text("Méthode et limites")
                .font(.system(size: 10, weight: .semibold))
            Text("L'état de santé est calculé à partir des données déclarées par le contrôleur du disque au moment de la lecture. Il reflète l'usure et les erreurs connues du disque, mais ne peut pas garantir l'absence de panne future. Sauvegardez régulièrement vos données.")
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#6E6E73"))
        }
    }
    
    private var smartTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(disk.physical.protocolType == .nvme ? "Détail NVMe SMART / Health" : "Attributs S.M.A.R.T.")
            
            HStack {
                Text("ID").frame(width: 40, alignment: .leading)
                Text("Attribut").frame(maxWidth: .infinity, alignment: .leading)
                Text("Valeur").frame(width: 120, alignment: .trailing)
                Text("État").frame(width: 80, alignment: .leading)
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(hex: "#6E6E73"))
            .padding(.vertical, 4)
            .background(Color(hex: "#F5F5F7"))
            
            if let snap = disk.snapshot {
                switch snap {
                case .nvme(let smart, let identify):
                    let attrs = NVMeAttributeCatalog.attributes(from: smart, identify: identify)
                    ForEach(Array(attrs.enumerated()), id: \.element.id) { index, attr in
                        HStack {
                            Text("0x\(String(format: "%02X", attr.id))")
                                .font(.system(size: 9.5, design: .monospaced))
                                .frame(width: 40, alignment: .leading)
                            Text(attr.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(attr.displayValue)
                                .frame(width: 120, alignment: .trailing)
                            Text(attr.state == .normal ? "Normal" : (attr.state == .warning ? "Attention" : (attr.state == .critical ? "Critique" : "—")))
                                .frame(width: 80, alignment: .leading)
                        }
                        .font(.system(size: 9.5))
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? Color.white : Color(hex: "#F5F5F7").opacity(0.3))
                    }
                case .ata(let ataSnap):
                    let profile = ATACatalog.profile(for: ataSnap.model)
                    ForEach(Array(ataSnap.attributes.enumerated()), id: \.element.id) { index, attr in
                        let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                        var stateStr = "Normal"
                        if attr.threshold > 0 && attr.current <= attr.threshold {
                            stateStr = "Critique"
                        } else if info.role == .reallocated || info.role == .pending || info.role == .uncorrectable {
                            if attr.rawValue > 0 { stateStr = "Attention" }
                        }
                        let displayValue = attr.value(for: info.role).map { Formatters.integer($0) } ?? "\(attr.current)"
                        
                        HStack {
                            Text("0x\(String(format: "%02X", attr.id))")
                                .font(.system(size: 9.5, design: .monospaced))
                                .frame(width: 40, alignment: .leading)
                            Text(info.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(displayValue)
                                .frame(width: 120, alignment: .trailing)
                            Text(stateStr)
                                .frame(width: 80, alignment: .leading)
                        }
                        .font(.system(size: 9.5))
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? Color.white : Color(hex: "#F5F5F7").opacity(0.3))
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#1D1D1F"))
            Divider().background(Color(hex: "#E5E5EA"))
        }
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#6E6E73"))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#1D1D1F"))
        }
    }
    
    private var statusColor: Color {
        switch disk.health.status {
        case .good: return Color(hex: "#248A3D")
        case .caution: return Color(hex: "#C93400")
        case .bad: return Color(hex: "#D70015")
        case .unknown: return Color(hex: "#6E6E73")
        }
    }
    
    private var statusString: String {
        switch disk.health.status {
        case .good: return "En bonne santé"
        case .caution: return "À surveiller"
        case .bad: return "Défaillance probable"
        case .unknown: return "Santé inconnue"
        }
    }
    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
