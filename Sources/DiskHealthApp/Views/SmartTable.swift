import SwiftUI
import DiskHealthCore

struct SmartAttribute: Identifiable {
    let id: Int
    let name: String
    let rawValue: UInt64
    let formattedValue: String
    let isWarning: Bool
    let isCritical: Bool
}

struct SmartTable: View {
    let smart: NVMeSmartLog
    let lastRead: Date
    
    var attributes: [SmartAttribute] {
        [
            SmartAttribute(id: 0x01, name: Strings.attr01, rawValue: UInt64(smart.criticalWarning), formattedValue: "0x\(String(format: "%02X", smart.criticalWarning))", isWarning: false, isCritical: smart.criticalWarning > 0),
            SmartAttribute(id: 0x02, name: Strings.attr02, rawValue: UInt64(smart.compositeTemperatureKelvin), formattedValue: smart.temperatureCelsius.map { Formatters.temperature($0) } ?? "—", isWarning: false, isCritical: false),
            SmartAttribute(id: 0x03, name: Strings.attr03, rawValue: UInt64(smart.availableSpare), formattedValue: "\(smart.availableSpare) %", isWarning: smart.availableSpare <= smart.availableSpareThreshold, isCritical: false),
            SmartAttribute(id: 0x04, name: Strings.attr04, rawValue: UInt64(smart.availableSpareThreshold), formattedValue: "\(smart.availableSpareThreshold) %", isWarning: false, isCritical: false),
            SmartAttribute(id: 0x05, name: Strings.attr05, rawValue: UInt64(smart.percentageUsed), formattedValue: "\(smart.percentageUsed) %", isWarning: smart.percentageUsed >= 90, isCritical: smart.percentageUsed >= 100),
            SmartAttribute(id: 0x06, name: Strings.attr06, rawValue: smart.dataUnitsRead, formattedValue: Formatters.dataUnitsToBytesText(smart.dataUnitsRead), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x07, name: Strings.attr07, rawValue: smart.dataUnitsWritten, formattedValue: Formatters.dataUnitsToBytesText(smart.dataUnitsWritten), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x08, name: Strings.attr08, rawValue: smart.hostReadCommands, formattedValue: Formatters.integer(smart.hostReadCommands), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x09, name: Strings.attr09, rawValue: smart.hostWriteCommands, formattedValue: Formatters.integer(smart.hostWriteCommands), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x0A, name: Strings.attr0A, rawValue: smart.controllerBusyTimeMinutes, formattedValue: Formatters.integer(smart.controllerBusyTimeMinutes), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x0B, name: Strings.attr0B, rawValue: smart.powerCycles, formattedValue: Formatters.integer(smart.powerCycles), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x0C, name: Strings.attr0C, rawValue: smart.powerOnHours, formattedValue: Formatters.integer(smart.powerOnHours), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x0D, name: Strings.attr0D, rawValue: smart.unsafeShutdowns, formattedValue: Formatters.integer(smart.unsafeShutdowns), isWarning: false, isCritical: false),
            SmartAttribute(id: 0x0E, name: Strings.attr0E, rawValue: smart.mediaErrors, formattedValue: Formatters.integer(smart.mediaErrors), isWarning: false, isCritical: smart.mediaErrors > 0),
            SmartAttribute(id: 0x0F, name: Strings.attr0F, rawValue: smart.errorLogEntries, formattedValue: Formatters.integer(smart.errorLogEntries), isWarning: smart.errorLogEntries > 0, isCritical: false)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Strings.smartTitle)
                    .font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let seconds = Int(Date().timeIntervalSince(lastRead))
                    Text("Lu il y a \(seconds) s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            
            Table(attributes) {
                TableColumn(Strings.smartColId) { attr in
                    Text(String(format: "0x%02X", attr.id))
                        .monospaced()
                        .foregroundColor(.secondary)
                }
                .width(40)
                
                TableColumn(Strings.smartColAttr) { attr in
                    Text(attr.name)
                        .foregroundColor(color(for: attr))
                }
                
                TableColumn(Strings.smartColRaw) { attr in
                    Text("0x\(String(format: "%02llX", attr.rawValue))")
                        .monospaced()
                        .foregroundColor(.secondary)
                }
                .width(140)
                
                TableColumn(Strings.smartColValue) { attr in
                    Text(attr.formattedValue)
                        .foregroundColor(color(for: attr))
                }
                .width(90)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func color(for attr: SmartAttribute) -> Color {
        if attr.isCritical {
            return Color(nsColor: .systemRed)
        } else if attr.isWarning {
            return Color(nsColor: .systemOrange)
        }
        return .primary
    }
}
