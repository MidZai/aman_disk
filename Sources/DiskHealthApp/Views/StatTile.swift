import SwiftUI
import DiskHealthCore

struct StatTile: View {
    let title: String
    let value: String
    let legend: String
    let customView: AnyView?
    
    init(title: String, value: String, legend: String, customView: AnyView? = nil) {
        self.title = title
        self.value = value
        self.legend = legend
        self.customView = customView
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            
            HStack(alignment: .bottom) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                
                if let custom = customView {
                    Spacer()
                    custom
                }
            }
            
            Spacer()
            Text(legend)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(height: 100, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
                    title: Strings.tileTemperature,
                    value: "Non transmise",
                    legend: ""
                )
                
                StatTile(
                    title: "Connexion",
                    value: "USB",
                    legend: ""
                )
                
                let vidStr = physical.usbVendorID.map { String(format: "%04X", $0) } ?? "----"
                let pidStr = physical.usbProductID.map { String(format: "%04X", $0) } ?? "----"
                
                StatTile(
                    title: "Pont USB",
                    value: "\(vidStr):\(pidStr)",
                    legend: ""
                )
            } else {
                // NVMe
                let tempStr = smart?.temperatureCelsius.map { Formatters.temperature($0) } ?? "Inconnue"
                let demoSparkline: [CGFloat] = [35.0, 36.0, 38.0, 40.0, 44.0, 42.0, 40.0, 39.0, 38.0, 38.0, 39.0, 40.0, 41.0, 39.0, 38.0, 38.0]
                
                StatTile(
                    title: Strings.tileTemperature,
                    value: tempStr,
                    legend: Strings.tileTemperatureHelp,
                    customView: AnyView(MiniSparkline(data: demoSparkline))
                )
                
                let written = smart?.dataUnitsWritten ?? 0
                let writtenStr = Formatters.dataUnitsToBytesText(written)
                let readStr = Formatters.dataUnitsToBytesText(smart?.dataUnitsRead ?? 0)
                
                StatTile(
                    title: Strings.tileDataWritten,
                    value: writtenStr,
                    legend: "\(readStr) lus depuis la mise en service"
                )
                
                StatTile(
                    title: Strings.tileLifeLeft,
                    value: "—", // In phase 5 it displays text in legend
                    legend: Strings.tileLifeLeftHelp
                )
            }
        }
    }
}
