import SwiftUI
import Charts
import DiskHealthCore

struct DiskDetailView: View {
    let disk: RealDisk
    
    @State private var historyRange: HistoryRange = .oneHour
    @State private var historySamples: [HistorySample] = []
    @State private var selectedPoint: AggregatedPoint? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            
            HStack {
                Text("Historique de température")
                    .font(.title3.bold())
                Spacer()
                Picker("Plage", selection: $historyRange) {
                    Text("1 heure").tag(HistoryRange.oneHour)
                    Text("24 heures").tag(HistoryRange.twentyFourHours)
                    Text("7 jours").tag(HistoryRange.sevenDays)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            
            let agg = HistoryAggregation.aggregate(samples: historySamples, range: historyRange)
            
            if agg.points.count < 2 {
                VStack {
                    Spacer()
                    Text("Données d'historique insuffisantes.\nLaissez l'application ouverte pour enregistrer la température.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
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
            
            if disk.smart != nil {
                SmartTableView(disk: disk)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: loadHistory)
        .onChange(of: disk.lastRead) { loadHistory() }
        .onChange(of: historyRange) { loadHistory() }
    }
    
    private func loadHistory() {
        if let identify = disk.identify {
            let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
            let since = Date().addingTimeInterval(-historyRange.timeInterval)
            historySamples = HistoryStore.shared.samples(for: key, since: since)
        }
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
        let maker = isApple ? "Apple" : "Générique"
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
