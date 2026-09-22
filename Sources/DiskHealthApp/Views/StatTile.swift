import SwiftUI
import DiskHealthCore

struct StatTile: View {
    let value: String
    let label: String
    let customView: AnyView?
    
    init(value: String, label: String, customView: AnyView? = nil) {
        self.value = value
        self.label = label
        self.customView = customView
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let custom = customView {
                    Spacer()
                    custom
                }
            }
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: 90, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

struct MiniSparkline: View {
    let data: [CGFloat]
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard data.count > 1 else { return }
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = maxVal - minVal == 0 ? 1 : maxVal - minVal
                
                let stepX = geo.size.width / CGFloat(data.count - 1)
                
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - ((val - minVal) / range) * geo.size.height
                    
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 112, height: 30)
    }
}

struct StatTilesRow: View {
    let physical: PhysicalDisk
    let snapshot: DiskHealthSnapshot?
    
    var body: some View {
        HStack(spacing: 12) {
            if physical.connection == .usb {
                StatTile(
                    value: "Non transmise",
                    label: "Température"
                )
                
                StatTile(
                    value: "USB",
                    label: "Connexion"
                )
                
                let vidStr = physical.usbVendorID.map { String(format: "%04X", $0) } ?? "----"
                let pidStr = physical.usbProductID.map { String(format: "%04X", $0) } ?? "----"
                
                StatTile(
                    value: "\(vidStr):\(pidStr)",
                    label: "Pont USB"
                )
            } else {
                let metrics = extractMetrics(snapshot: snapshot, isRotational: physical.mediumType == .rotational)
                let isDemo = ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1"
                
                StatTile(
                    value: metrics.tempStr,
                    label: isDemo ? Strings.tileTemperatureHelp : (metrics.hasTemp ? "Température" : "Non fourni par ce disque"),
                    customView: isDemo && metrics.hasTemp ? AnyView(MiniSparkline(data: [35.0, 36.0, 38.0, 40.0, 44.0, 42.0, 40.0, 39.0, 38.0, 38.0, 39.0, 40.0, 41.0, 39.0, 38.0, 38.0])) : nil
                )
                
                StatTile(
                    value: metrics.hoursStr,
                    label: metrics.hasHours ? "Heures d'utilisation" : "Non fourni par ce disque"
                )
                
                StatTile(
                    value: metrics.cyclesStr,
                    label: metrics.hasCycles ? "Cycles d'alimentation" : "Non fourni par ce disque"
                )
                
                StatTile(
                    value: metrics.unsafeStr,
                    label: metrics.hasUnsafe ? "Arrêts non propres" : "Non fourni par ce disque"
                )
                
                StatTile(
                    value: metrics.errorsStr,
                    label: metrics.hasErrors ? "Secteurs défectueux" : "Non fourni par ce disque"
                )
            }
        }
    }
    
    private struct ExtractedMetrics {
        let tempStr: String
        let hoursStr: String
        let cyclesStr: String
        let unsafeStr: String
        let errorsStr: String
        
        let hasTemp: Bool
        let hasHours: Bool
        let hasCycles: Bool
        let hasUnsafe: Bool
        let hasErrors: Bool
    }
    
    private func extractMetrics(snapshot: DiskHealthSnapshot?, isRotational: Bool) -> ExtractedMetrics {
        guard let snap = snapshot else {
            return ExtractedMetrics(tempStr: "—", hoursStr: "—", cyclesStr: "—", unsafeStr: "—", errorsStr: "—", hasTemp: false, hasHours: false, hasCycles: false, hasUnsafe: false, hasErrors: false)
        }
        
        var temp: Int? = nil
        var hours: UInt64? = nil
        var cycles: UInt64? = nil
        var unsafe: UInt64? = nil
        var errors: UInt64? = nil
        
        switch snap {
        case .nvme(let smart, _):
            temp = smart.temperatureCelsius
            hours = smart.powerOnHours
            cycles = smart.powerCycles
            unsafe = smart.unsafeShutdowns
            errors = smart.mediaErrors
        case .ata(let ataSnap):
            let profile = ATACatalog.profile(for: ataSnap.model)
            for attr in ataSnap.attributes {
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                if info.role == .temperature {
                    temp = attr.value(for: .temperature).map { Int($0) }
                }
                if info.role == .powerOnHours {
                    hours = attr.value(for: .powerOnHours)
                }
                if info.role == .powerCycles {
                    cycles = attr.value(for: .powerCycles)
                }
                if info.role == .unsafeShutdowns {
                    unsafe = attr.value(for: .unsafeShutdowns)
                }
                if info.role == .reallocated || info.role == .pending || info.role == .uncorrectable {
                    errors = (errors ?? 0) + attr.rawValue
                }
            }
        }
        
        return ExtractedMetrics(
            tempStr: temp != nil ? Formatters.temperature(temp!) : "—",
            hoursStr: hours != nil ? Formatters.hours(hours!) : "—",
            cyclesStr: cycles != nil ? Formatters.cycles(cycles!) : "—",
            unsafeStr: unsafe != nil ? Formatters.integer(unsafe!) : "—",
            errorsStr: errors != nil ? Formatters.integer(errors!) : "—",
            hasTemp: temp != nil,
            hasHours: hours != nil,
            hasCycles: cycles != nil,
            hasUnsafe: unsafe != nil,
            hasErrors: errors != nil
        )
    }
}
