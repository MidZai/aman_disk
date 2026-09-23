import SwiftUI
import Charts
import DiskHealthCore

struct DiskDetailView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk
    
    @State private var showSerial = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            header
            
            if disk.snapshot != nil {
                StatTilesRow(physical: disk.physical, snapshot: disk.snapshot)
            }
            
            Divider()
            
            TemperatureHistoryView(historyKey: appManager.historyKey(for: disk), lastRead: disk.lastRead)
            
            if disk.snapshot != nil {
                SmartTableView(disk: disk)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 1400, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            HealthRingView(health: disk.health, capability: disk.physical.healthCapability)
                .frame(width: 96, height: 96)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(disk.physical.model)
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 12, height: 12)
                    Text(healthLabel)
                        .font(.headline)
                }
                
                Text(subtext)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    InfoPair(label: "Capacité", value: sizeStr)
                    InfoPair(label: "Interface", value: interfaceStr)
                    InfoPair(label: "Emplacement", value: locationStr)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    InfoPair(label: "Firmware", value: disk.firmware ?? "—")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("N° de série")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if showSerial {
                                Text(disk.serialNumber ?? "—")
                                    .font(.body)
                            } else {
                                Text(disk.serialNumber != nil ? "Masqué" : "—")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            if disk.serialNumber != nil {
                                Button(action: { showSerial.toggle() }) {
                                    Image(systemName: showSerial ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dernière lecture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                            let diff = Int(timeline.date.timeIntervalSince(disk.lastRead))
                            Text("il y a \(diff) s")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // P6: Use HealthStatus extension instead of a duplicated switch.
    private var healthColor: Color { disk.health.status.color }

    // I7: Use Strings constants for localised labels, matching Strings.swift.
    private var healthLabel: String {
        let label = disk.health.status.localizedLabel
        if disk.health.status == .good || disk.health.status == .unknown {
            return label
        }
        // Show first reason in parentheses only when it's short enough (< 60 chars).
        if let reason = disk.health.reasons.first, reason.count < 60 {
            return "\(label) (\(reason))"
        }
        return label
    }

    
    private var subtext: String {
        let typeStr = disk.physical.mediumType == .solidState ? "SSD" : (disk.physical.mediumType == .rotational ? "Disque dur" : "Support")
        let locStr = disk.physical.isInternal ? "interne" : "externe"
        var protoStr = ""
        switch disk.physical.protocolType {
        case .nvme: protoStr = "NVMe"
        case .pcieAhci: protoStr = "PCIe AHCI"
        case .ata: protoStr = "SATA"
        case .usb: protoStr = "USB"
        default: protoStr = disk.physical.connection.rawValue
        }
        var str = "\(typeStr) \(locStr) · \(protoStr)"
        if disk.physical.mediumType == .rotational, let snap = disk.snapshot, case .ata(let ataSnap) = snap, ataSnap.rotationRate > 1 {
            str += " · \(ataSnap.rotationRate) tr/min"
        }
        if appManager.isFusionDriveMember(disk) {
            str += " · \(Strings.fusionDriveMember)"
        }
        return str
    }
    
    private var sizeStr: String {
        return Formatters.bytes(disk.physical.sizeBytes)
    }
    
    private var interfaceStr: String {
        if disk.physical.protocolType == .pcieAhci {
            return "PCIe AHCI"
        }
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
    
}

struct InfoPair: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}
