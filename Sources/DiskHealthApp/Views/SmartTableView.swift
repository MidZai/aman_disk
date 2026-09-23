import SwiftUI
import DiskHealthCore

// MARK: - UnifiedAttribute

struct UnifiedAttribute: Identifiable {
    let id: UInt8
    let name: String              // French catalog name
    let technicalName: String // Technical name → shown in ⓘ popover
    let explanation: String
    /// Normalized value (0-255 for ATA, formatted value for NVMe)
    let valueCurrent: String
    /// Worst ever (ATA only)
    let worst: String?
    /// Threshold (ATA only)
    let threshold: String?
    /// Interpreted / human-readable value (e.g. "40 °C", "31 495 h")
    let donnee: String
    /// 6 raw bytes as hex (e.g. "0x00000000 7B07")
    let rawHex: String
    let state: AttributeState
    let isInformational: Bool
}

// MARK: - SmartTableView

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
                    let unified = attrs.map { a -> UnifiedAttribute in
                        UnifiedAttribute(
                            id: a.id,
                            name: a.name,
                            technicalName: a.name,  // NVMe names are already technical
                            explanation: a.explanation,
                            valueCurrent: a.displayValue,
                            worst: nil,
                            threshold: nil,
                            donnee: a.displayValue,
                            rawHex: a.rawValue,
                            state: a.state,
                            isInformational: a.state == .informational
                        )
                    }
                    nvmeTable(unified)

                case .ata(let ataSnap):
                    let profile = ATACatalog.profile(for: ataSnap.model)
                    let unified = ataSnap.attributes.map { attr -> UnifiedAttribute in
                        let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)

                        // Determine state
                        var state: AttributeState = .normal
                        if attr.threshold > 0 && attr.current <= attr.threshold {
                            state = .critical
                        } else if info.role == .reallocated || info.role == .pending || info.role == .uncorrectable {
                            if attr.rawValue > 0 { state = .warning }
                        }

                        // Donnée: human-readable interpretation
                        let donnee: String
                        switch info.role {
                        case .temperature:
                            if let t = attr.value(for: info.role) { donnee = "\(t) °C" }
                            else { donnee = "—" }
                        case .powerOnHours:
                            if let h = attr.value(for: info.role) { donnee = Formatters.hours(h) }
                            else { donnee = "—" }
                        case .powerCycles, .unsafeShutdowns:
                            if let v = attr.value(for: info.role) { donnee = Formatters.integer(v) }
                            else { donnee = "—" }
                        case .reallocated, .pending, .uncorrectable:
                            donnee = Formatters.integer(attr.rawValue)
                        case .hostWritesBytes(let mult):
                            let bytes = attr.rawValue * mult
                            donnee = Formatters.bytes(bytes)
                        case .hostReadsBytes(let mult):
                            let bytes = attr.rawValue * mult
                            donnee = Formatters.bytes(bytes)
                        case .lifeRemainingPercentNormalized:
                            donnee = "\(attr.current) %"
                        case .none:
                            donnee = "—"
                        }

                        // Raw hex: 6 bytes split "0xXXXXXXXX XXXX"
                        let rawArr = attr.raw  // [UInt8], 6 bytes, LSB first
                        // Pad to 6 if shorter
                        var r = Array(rawArr.prefix(6))
                        while r.count < 6 { r.append(0) }
                        let hi32 = String(format: "%02X%02X%02X%02X", r[3], r[2], r[1], r[0])
                        let lo16 = String(format: "%02X%02X", r[5], r[4])
                        let rawHex = "0x\(hi32) \(lo16)"

                        let thresholdStr = attr.threshold == 0 ? "—" : "\(attr.threshold)"
                        let isInfo = state == .informational

                        // Extract the technical name from the explanation (after "\n\nNom technique : ")
                        let stName: String
                        if let range = info.explanation.range(of: "\n\nNom technique : ") {
                            stName = String(info.explanation[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            stName = ""
                        }
                        // Explanation without the technical name suffix
                        let cleanExpl: String
                        if let range = info.explanation.range(of: "\n\nNom technique : ") {
                            cleanExpl = String(info.explanation[..<range.lowerBound])
                        } else {
                            cleanExpl = info.explanation
                        }

                        return UnifiedAttribute(
                            id: attr.id,
                            name: info.name,
                            technicalName: stName,
                            explanation: cleanExpl,
                            valueCurrent: "\(attr.current)",
                            worst: "\(attr.worst)",
                            threshold: thresholdStr,
                            donnee: donnee,
                            rawHex: rawHex,
                            state: state,
                            isInformational: isInfo
                        )
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

    // MARK: - Header

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

    // MARK: - NVMe table

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
                Text(attr.valueCurrent)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(weight(for: attr.state))
                    .foregroundColor(color(for: attr.state))
                    .padding(.vertical, 6)
                    .contextMenu { contextMenu(for: attr) }
            }.width(180)

            TableColumn(appManager.showRawValues ? "Brute" : "Donnée") { attr in
                if appManager.showRawValues {
                    Text(attr.rawHex)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                } else {
                    Text(attr.donnee)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }.width(180)

            TableColumn("État") { attr in
                stateCell(attr)
            }.width(100)
        }
        .environment(\.defaultMinListRowHeight, 32)
        .tableStyle(.bordered)
        .frame(minHeight: CGFloat(38 + (attrs.count * 32)))
    }

    // MARK: - ATA table

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

            TableColumn("Valeur") { attr in
                Text(attr.valueCurrent)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(weight(for: attr.state))
                    .foregroundColor(color(for: attr.state))
                    .padding(.vertical, 6)
                    .contextMenu { contextMenu(for: attr) }
            }.width(70)

            TableColumn("Pire") { attr in
                Text(attr.worst ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 6)
            }.width(55)

            TableColumn("Seuil") { attr in
                Text(attr.threshold ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 6)
            }.width(55)

            TableColumn(appManager.showRawValues ? "Brute" : "Donnée") { attr in
                if appManager.showRawValues {
                    Text(attr.rawHex)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                } else {
                    Text(attr.donnee)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }.width(appManager.showRawValues ? 160 : 120)

            TableColumn("État") { attr in
                stateCell(attr)
            }.width(100)
        }
        .environment(\.defaultMinListRowHeight, 32)
        .tableStyle(.bordered)
        .frame(minHeight: CGFloat(38 + (attrs.count * 32)))
    }

    // MARK: - Cells

    @ViewBuilder private func idCell(_ attr: UnifiedAttribute) -> some View {
        let hex = String(format: "0x%02X", attr.id)
        Text(hex)
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.vertical, 6)
            .contextMenu { contextMenu(for: attr) }
    }

    @ViewBuilder private func stateCell(_ attr: UnifiedAttribute) -> some View {
        HStack(spacing: 8) {
            if attr.isInformational {
                Text("—").foregroundColor(.secondary)
            } else {
                Circle()
                    .fill(color(for: attr.state))
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
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(attr.donnee, forType: .string)
        }
        Button("Copier la ligne") {
            NSPasteboard.general.clearContents()
            let hexID = String(format: "0x%02X", attr.id)
            NSPasteboard.general.setString("\(hexID) \(attr.name) : \(attr.donnee)", forType: .string)
        }
    }

    private func color(for state: AttributeState) -> Color { state.tableColor }
    private func stateLabel(_ state: AttributeState) -> String { state.localizedLabel }
    private func weight(for state: AttributeState) -> Font.Weight { state.fontWeight }
}

// MARK: - AttributeCell

struct AttributeCell: View {
    let attr: UnifiedAttribute
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(attr.name)
                .fontWeight(attr.state.fontWeight)
                .foregroundColor(attr.state.tableColor)

            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverView
            }
        }
    }

    private var popoverView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(attr.name).font(.headline)
            if !attr.technicalName.isEmpty {
                Text("Nom technique : \(attr.technicalName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()
            Text(attr.explanation).font(.callout)
            if attr.donnee != "—" {
                Text("Valeur interprétée : \(attr.donnee)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
