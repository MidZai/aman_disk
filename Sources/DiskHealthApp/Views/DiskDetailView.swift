import SwiftUI
import Charts
import DiskHealthCore

struct DiskDetailView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk
    
    @State private var historyRange: HistoryRange = .oneHour
    @State private var historySamples: [HistorySample] = []
    @State private var selectedPoint: AggregatedPoint? = nil
    @State private var showSerial = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            header
            
            if disk.snapshot != nil {
                StatTilesRow(physical: disk.physical, snapshot: disk.snapshot)
            }
            
            Divider()
            
            HStack {
                Text("Historique de température")
                    .font(.title3.bold())
                Spacer()
                Picker("", selection: $historyRange) {
                    Text("1 heure").tag(HistoryRange.oneHour)
                    Text("24 heures").tag(HistoryRange.twentyFourHours)
                    Text("7 jours").tag(HistoryRange.sevenDays)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
            }
            
            let agg = HistoryAggregation.aggregate(samples: historySamples, range: historyRange)
            
            if agg.points.count < 2 {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Aucune donnée historique disponible")
                        .font(.headline)
                    Text("L'application commencera à enregistrer la température\ndès que le disque sera surveillé.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let yMin = max(0, (agg.min ?? 0) - 5)
                let yMax = min(100, (agg.max ?? 0) + 5)
                
                Chart {
                    ForEach(agg.points) { point in
                        LineMark(
                            x: .value("Heure", point.date),
                            y: .value("Temp", point.temperature),
                            series: .value("Segment", point.segment)
                        )
                        .foregroundStyle(Color.blue)
                        
                        AreaMark(
                            x: .value("Heure", point.date),
                            y: .value("Temp", point.temperature),
                            series: .value("Segment", point.segment)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .alignsMarkStylesWithPlotArea(true)
                    }
                    
                    if let selected = selectedPoint {
                        RuleMark(
                            x: .value("Heure", selected.date)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(Color.gray)
                        .annotation(position: .top) {
                            VStack(alignment: .leading) {
                                Text(selected.date.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(Int(round(selected.temperature))) °C")
                                    .font(.caption.bold())
                            }
                            .padding(6)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                            .cornerRadius(6)
                            .shadow(radius: 2)
                        }
                    }
                }
                .chartYScale(domain: yMin...yMax)
                .chartXAxis {
                    AxisMarks(preset: .aligned)
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned)
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        // Find closest point
                                        selectedPoint = agg.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                    }
                                case .ended:
                                    selectedPoint = nil
                                }
                            }
                    }
                }
            }
            
            if disk.snapshot != nil {
                SmartTableView(disk: disk)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 1400, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
        }
        .onAppear(perform: loadHistory)
        .onChange(of: disk.lastRead) { loadHistory() }
        .onChange(of: historyRange) { loadHistory() }
    }
    
    private func loadHistory() {
        // I6: disk.identify returns NVMeIdentify? and is nil for ATA disks.
        // Derive the history key from the snapshot type instead.
        let key: String?
        switch disk.snapshot {
        case .nvme(_, let id):
            key = DiskIdentity.key(model: id.modelNumber, serial: id.serialNumber)
        case .ata(let ataSnap):
            key = DiskIdentity.key(model: ataSnap.model, serial: ataSnap.serialNumber)
        case nil:
            key = nil
        }
        guard let key else { return }
        let since = Date().addingTimeInterval(-historyRange.timeInterval)
        historySamples = HistoryStore.shared.samples(for: key, since: since)
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
