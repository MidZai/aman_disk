import SwiftUI
import DiskHealthCore

struct DiskDetailView: View {
    let disk: RealDisk
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            DiskIconProvider.icon(for: disk)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(disk.physical.model)
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 12, height: 12)
                    Text(healthLabel)
                        .font(.title3)
                }
                
                Text(subtext)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    Text("Capacité").foregroundColor(.secondary)
                    Text(sizeStr)
                    
                    Text("Firmware").foregroundColor(.secondary)
                    Text(disk.identify?.firmwareRevision ?? "—")
                }
                GridRow {
                    Text("Interface").foregroundColor(.secondary)
                    Text(interfaceStr)
                    
                    Text("N° de série").foregroundColor(.secondary)
                    Text(serialStr)
                }
                GridRow {
                    Text("Emplacement").foregroundColor(.secondary)
                    Text(locationStr)
                    
                    Text("Dernière lecture").foregroundColor(.secondary)
                    TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                        let diff = Int(timeline.date.timeIntervalSince(disk.lastRead))
                        Text("il y a \(diff) s")
                    }
                }
            }
            .font(.body)
        }
    }
    
    private var healthColor: Color {
        switch disk.health.status {
        case .good: return .green
        case .caution: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }
    
    private var healthLabel: String {
        let statusText: String
        switch disk.health.status {
        case .good: statusText = "En bonne santé"
        case .caution: statusText = "Attention"
        case .bad: statusText = "Critique"
        case .unknown: statusText = "Inconnu"
        }
        
        if disk.health.status == .good {
            return statusText
        } else {
            let reason = disk.health.reasons.first ?? ""
            return "\(statusText) (\(reason))"
        }
    }
    
    private var subtext: String {
        let isApple = disk.physical.model.uppercased().contains("APPLE")
        let maker = isApple ? "Apple" : "Générique" // Could be better but suffices
        let loc = disk.physical.isInternal ? "Disque interne" : "Disque externe"
        return "\(loc) · \(maker)"
    }
    
    private var sizeStr: String {
        let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
        return String(format: "%.1f Go", sizeGB)
    }
    
    private var interfaceStr: String {
        switch disk.physical.connection {
        case .nvmeInternal, .nvmeExternal: return "NVMe"
        case .sata: return "SATA"
        case .usb: return "USB"
        case .other: return "Autre"
        }
    }
    
    private var locationStr: String {
        disk.physical.isInternal ? "Interne" : "Externe"
    }
    
    private var serialStr: String {
        guard let s = disk.identify?.serialNumber, s.count > 4 else {
            return disk.identify?.serialNumber ?? "—"
        }
        let suffix = s.suffix(4)
        return "••••\(suffix)"
    }
}
