import SwiftUI
import DiskHealthCore

struct InfoList: View {
    let physical: PhysicalDisk
    let smart: NVMeSmartLog?
    let identify: NVMeIdentify?
    
    @State private var serialVisible = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.infoTitle)
                .font(.headline)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                InfoRow(label: Strings.infoCapacity, value: Formatters.bytes(physical.sizeBytes), isLast: false)
                
                let interface = physical.isInternal ? "NVMe (Interne)" : (physical.connection == .usb ? "USB" : "NVMe (Externe)")
                InfoRow(label: Strings.infoInterface, value: interface, isLast: false)
                
                InfoRow(label: Strings.infoFirmware, value: identify?.firmwareRevision ?? "—", isLast: false)
                
                // Serial row is custom due to button
                serialRow
                
                InfoRow(label: Strings.infoPowerOnHours, value: smart.map { Formatters.hours($0.powerOnHours) } ?? "—", isLast: false)
                InfoRow(label: Strings.infoPowerCycles, value: smart.map { Formatters.integer($0.powerCycles) } ?? "—", isLast: false)
                InfoRow(label: Strings.infoUnsafeShutdowns, value: smart.map { Formatters.integer($0.unsafeShutdowns) } ?? "—", isLast: false)
                
                let mediaErrs = smart?.mediaErrors ?? 0
                InfoRow(label: Strings.infoMediaErrors, value: smart.map { Formatters.integer($0.mediaErrors) } ?? "—", isLast: true, valueColor: mediaErrs > 0 ? Color(nsColor: .systemRed) : .secondary)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(width: 360)
    }
    
    private var serialRow: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Strings.infoSerial)
                Spacer()
                
                HStack(spacing: 8) {
                    if let serial = identify?.serialNumber {
                        if serialVisible {
                            Text(serial)
                                .foregroundColor(.secondary)
                                .monospaced()
                        } else {
                            let last4 = String(serial.suffix(4))
                            Text("•••• •••• •••• \(last4)")
                                .foregroundColor(.secondary)
                                .monospaced()
                        }
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                    
                    if identify?.serialNumber != nil {
                        Button(serialVisible ? Strings.actionHide : Strings.actionShow) {
                            serialVisible.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 16)
            
            Divider()
                .padding(.leading, 16)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let isLast: Bool
    var valueColor: Color = .secondary
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundColor(valueColor)
            }
            .frame(height: 34)
            .padding(.horizontal, 16)
            
            if !isLast {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}
