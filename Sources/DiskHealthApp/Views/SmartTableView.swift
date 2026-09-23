import SwiftUI
import DiskHealthCore

struct UnifiedAttribute: Identifiable {
    let id: UInt8
    let name: String
    let explanation: String
    let current: String
    let worst: String?
    let threshold: String?
    let rawValue: String
    let state: AttributeState
    let isInformational: Bool
}

struct SmartTableView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            if let snap = disk.snapshot {
                switch snap {
                case .nvme(let smartLog, let identify):
                    let attrs = NVMeAttributeCatalog.attributes(from: smartLog, identify: identify)
                    let unified = attrs.map { UnifiedAttribute(id: $0.id, name: $0.name, explanation: $0.explanation, current: $0.displayValue, worst: nil, threshold: nil, rawValue: $0.rawValue, state: $0.state, isInformational: $0.state == .informational) }
                    nvmeTable(unified)
                case .ata(let ataSnap):
                    let profile = ATACatalog.profile(for: ataSnap.model)
                    let unified = ataSnap.attributes.map { attr -> UnifiedAttribute in
                        let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                        var state: AttributeState = .normal
                        if attr.threshold > 0 && attr.current <= attr.threshold {
                            state = .critical
                        } else if info.role == .reallocated || info.role == .pending || info.role == .uncorrectable {
                            if attr.rawValue > 0 { state = .warning }
                        }
                        
                        let displayValue = attr.value(for: info.role).map { Formatters.integer($0) } ?? "\(attr.current)"
                        let thresholdStr = attr.threshold == 0 ? "—" : "\(attr.threshold)"
                        let isInfo = state == .informational
                        
                        return UnifiedAttribute(id: attr.id, name: info.name, explanation: info.explanation, current: "\(attr.current) (\(displayValue))", worst: "\(attr.worst)", threshold: thresholdStr, rawValue: "\(attr.rawValue)", state: state, isInformational: isInfo)
                    }
                    ataTable(unified)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Attributs S.M.A.R.T.")
                    .font(.headline)
                
                if let snap = disk.snapshot {
                    switch snap {
                    case .nvme:
                        Text("Journal NVMe SMART / Health Information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .ata(let ata):
                        Text("ATA S.M.A.R.T.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !ata.checksumValid {
                            Text("Données non vérifiées (somme de contrôle incorrecte)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if !ata.thresholdsChecksumValid {
                            Text("Seuils non vérifiés (somme de contrôle incorrecte)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()
            
            Toggle("Valeurs brutes", isOn: $appManager.showRawValues.animation(.easeInOut(duration: 0.2)))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
    
    private func nvmeTable(_ attrs: [UnifiedAttribute]) -> some View {
        Table(attrs) {
            TableColumn("ID") { attr in
                idCell(attr)
            }.width(40)
            
            TableColumn("Attribut") { attr in
                AttributeCell(attr: attr)
                    .padding(.vertical, 6)
                    .contextMenu { contextMenu(for: attr) }
            }
            
            TableColumn("Valeur") { attr in
                valCell(attr)
            }.width(180)
            
            TableColumn("Valeur brute") { attr in
                if appManager.showRawValues { rawCell(attr) }
            }.width(appManager.showRawValues ? 150 : 0)
            
            TableColumn("État") { attr in
                stateCell(attr)
            }.width(100)
        }
        .environment(\.defaultMinListRowHeight, 32)
        .tableStyle(.bordered)
        .frame(minHeight: CGFloat(38 + (attrs.count * 32)))
    }
    
    private func ataTable(_ attrs: [UnifiedAttribute]) -> some View {
        Table(attrs) {
            TableColumn("ID") { attr in
                idCell(attr)
            }.width(40)
            
            TableColumn("Attribut") { attr in
                AttributeCell(attr: attr)
                    .padding(.vertical, 6)
                    .contextMenu { contextMenu(for: attr) }
            }
            
            TableColumn("Actuelle") { attr in
                valCell(attr)
            }.width(140)
            
            TableColumn("Pire") { attr in
                Text(attr.worst ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 6)
            }.width(60)
            
            TableColumn("Seuil") { attr in
                Text(attr.threshold ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 6)
            }.width(60)
            
            TableColumn("Valeur brute") { attr in
                if appManager.showRawValues { rawCell(attr) }
            }.width(appManager.showRawValues ? 150 : 0)
            
            TableColumn("État") { attr in
                stateCell(attr)
            }.width(100)
        }
        .environment(\.defaultMinListRowHeight, 32)
        .tableStyle(.bordered)
        .frame(minHeight: CGFloat(38 + (attrs.count * 32)))
    }

    
    @ViewBuilder private func idCell(_ attr: UnifiedAttribute) -> some View {
        let hex = "0x" + String(format: "%02X", attr.id)
        Text(hex)
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.vertical, 6)
            .contextMenu { contextMenu(for: attr) }
    }
    
    @ViewBuilder private func valCell(_ attr: UnifiedAttribute) -> some View {
        Text(attr.current)
            .font(.system(.body, design: .monospaced))
            .fontWeight(weight(for: attr.state))
            .foregroundColor(color(for: attr.state, isValue: true))
            .padding(.vertical, 6)
            .contextMenu { contextMenu(for: attr) }
    }
    
    @ViewBuilder private func rawCell(_ attr: UnifiedAttribute) -> some View {
        Text(attr.rawValue)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .padding(.vertical, 6)
            .contextMenu { contextMenu(for: attr) }
    }
    
    @ViewBuilder private func stateCell(_ attr: UnifiedAttribute) -> some View {
        HStack(spacing: 8) {
            if attr.isInformational {
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
    
    @ViewBuilder
    private func contextMenu(for attr: UnifiedAttribute) -> some View {
        Button("Copier la valeur") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(attr.current, forType: .string)
        }
        Button("Copier la ligne") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let hexID = "0x" + String(format: "%02X", attr.id)
            pasteboard.setString("\(hexID) \(attr.name) : \(attr.current)", forType: .string)
        }
    }
    
    // P6: Replaced by AttributeState extension below.
    private func color(for state: AttributeState, isValue: Bool) -> Color {
        state.tableColor
    }
    
    private func stateLabel(_ state: AttributeState) -> String {
        state.localizedLabel
    }
    
    private func weight(for state: AttributeState) -> Font.Weight {
        state.fontWeight
    }
}


struct PopoverView: View {
    let attr: UnifiedAttribute
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(attr.name).font(.headline)
            Text(attr.explanation).font(.callout)
            Text("Valeur : \(attr.current) (brut: \(attr.rawValue))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}

struct AttributeCell: View {
    let attr: UnifiedAttribute
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
    
    // P6: Delegate to AttributeState extension for consistency.
    private func color(for state: AttributeState, isValue: Bool) -> Color { state.tableColor }
    private func weight(for state: AttributeState) -> Font.Weight { state.fontWeight }
}

