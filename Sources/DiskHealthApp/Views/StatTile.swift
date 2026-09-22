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
    let smart: NVMeSmartLog?
    
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
                let tempStr = smart?.temperatureCelsius.map { Formatters.temperature($0) } ?? "Inconnue"
                let isDemo = ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1"
                
                StatTile(
                    value: tempStr,
                    label: isDemo ? Strings.tileTemperatureHelp : "Température",
                    customView: isDemo ? AnyView(MiniSparkline(data: [35.0, 36.0, 38.0, 40.0, 44.0, 42.0, 40.0, 39.0, 38.0, 38.0, 39.0, 40.0, 41.0, 39.0, 38.0, 38.0])) : nil
                )
                
                let hours = smart?.powerOnHours ?? 0
                StatTile(
                    value: Formatters.hours(hours),
                    label: "Heures d'utilisation"
                )
                
                let cycles = smart?.powerCycles ?? 0
                StatTile(
                    value: Formatters.cycles(cycles),
                    label: "Cycles d'alimentation"
                )
                
                let unsafe = smart?.unsafeShutdowns ?? 0
                StatTile(
                    value: Formatters.integer(unsafe),
                    label: "Arrêts non propres"
                )
                
                let errors = smart?.mediaErrors ?? 0
                StatTile(
                    value: Formatters.integer(errors),
                    label: "Erreurs média"
                )
            }
        }
    }
}

