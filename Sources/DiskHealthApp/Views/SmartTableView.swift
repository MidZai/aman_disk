import SwiftUI
import DiskHealthCore

struct SmartTableView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk
    
    @State private var popoverAttribute: NVMeAttribute?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attributs S.M.A.R.T.")
                        .font(.headline)
                    Text("Journal NVMe SMART / Health Information")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Toggle("Valeurs brutes", isOn: $appManager.showRawValues.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            let attrs = NVMeAttributeCatalog.attributes(from: disk.smart!, identify: disk.identify)
            
            Table(attrs) {
                TableColumn("ID") { attr in
                    Text("0x" + String(format: "%02X", attr.id))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                        .contextMenu { contextMenu(for: attr) }
                }
                .width(40)
                
                TableColumn("Attribut") { attr in
                    AttributeCell(attr: attr)
                        .padding(.vertical, 6)
                        .contextMenu { contextMenu(for: attr) }
                }
                
                TableColumn("Valeur") { attr in
                    Text(attr.displayValue)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(weight(for: attr.state))
                        .foregroundColor(color(for: attr.state, isValue: true))
                        .padding(.vertical, 6)
                        .contextMenu { contextMenu(for: attr) }
                }
                .width(180)
                
                TableColumn("Valeur brute") { attr in
                    if appManager.showRawValues {
                        Text(attr.rawValue)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                            .contextMenu { contextMenu(for: attr) }
                    }
                }
                .width(appManager.showRawValues ? 150 : 0)
                
                TableColumn("État") { attr in
                    HStack(spacing: 8) {
                        if attr.state == .informational {
                            Text("—").foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(color(for: attr.state, isValue: false))
                                .frame(width: 8, height: 8)
                            
                            Text(stateLabel(attr.state))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.vertical, 6)
                    .contextMenu { contextMenu(for: attr) }
                }
                .width(100)
            }
            .environment(\.defaultMinListRowHeight, 32)
            .tableStyle(.bordered)
            .frame(height: 38 + (15 * 32))
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func contextMenu(for attr: NVMeAttribute) -> some View {
        Button("Copier la valeur") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(attr.displayValue, forType: .string)
        }
        Button("Copier la ligne") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let hexID = "0x" + String(format: "%02X", attr.id)
            pasteboard.setString("\(hexID) \(attr.name) : \(attr.displayValue)", forType: .string)
        }
    }
    
    private func color(for state: AttributeState, isValue: Bool) -> Color {
        switch state {
        case .normal, .informational: return isValue ? .primary : .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    private func stateLabel(_ state: AttributeState) -> String {
        switch state {
        case .normal: return "Normal"
        case .warning: return "Attention"
        case .critical: return "Critique"
        case .informational: return "—"
        }
    }
    
    private func weight(for state: AttributeState) -> Font.Weight {
        return (state == .warning || state == .critical) ? .semibold : .regular
    }
}

struct PopoverView: View {
    let attr: NVMeAttribute
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(attr.name).font(.headline)
            Text(attr.explanation).font(.callout)
            Text("Valeur actuelle : \(attr.displayValue) (brut: \(attr.rawValue))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}

struct AttributeCell: View {
    let attr: NVMeAttribute
    @State private var showPopover = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(attr.name)
                .fontWeight(weight(for: attr.state))
                .foregroundColor(color(for: attr.state, isValue: false))
            
            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                PopoverView(attr: attr)
            }
        }
    }
    
    private func color(for state: AttributeState, isValue: Bool) -> Color {
        switch state {
        case .normal, .informational: return isValue ? .primary : .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    private func weight(for state: AttributeState) -> Font.Weight {
        return (state == .warning || state == .critical) ? .semibold : .regular
    }
}
