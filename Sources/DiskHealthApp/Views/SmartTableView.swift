import SwiftUI
import DiskHealthCore

// MARK: - Shared NVMe / ATA model

struct UnifiedAttribute: Identifiable {
    let id: UInt8
    let name: String
    /// Technical attribute name, shown in the help tooltip.
    let technicalName: String
    let explanation: String
    /// Normalized value (ATA only: 0 to 255, higher is better).
    let current: String?
    let worst: String?
    let threshold: String?
    /// Interpreted value, with its unit (“40 °C”, “31,495 h”, “12.3 TB”).
    let value: String
    /// Raw value in hexadecimal.
    let rawHex: String
    let state: AttributeState

    var hexID: String { String(format: "0x%02X", id) }
}

enum SmartRows {
    static func rows(for snapshot: DiskHealthSnapshot) -> [UnifiedAttribute] {
        switch snapshot {
        case .nvme(let log, let identify):
            return NVMeAttributeCatalog.attributes(from: log, identify: identify).map { a in
                UnifiedAttribute(id: a.id, name: a.name, technicalName: "", explanation: a.explanation,
                                 current: nil, worst: nil, threshold: nil,
                                 value: a.displayValue, rawHex: a.rawValue, state: a.state)
            }
        case .ata(let ata):
            let profile = ATACatalog.profile(for: ata.model)
            return ata.attributes.map { attr in
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                let (explanation, technical) = split(info.explanation)
                return UnifiedAttribute(
                    id: attr.id,
                    name: info.name,
                    technicalName: technical,
                    explanation: explanation,
                    current: "\(attr.current)",
                    worst: "\(attr.worst)",
                    threshold: attr.threshold == 0 ? "—" : "\(attr.threshold)",
                    value: interpretedValue(attr, role: info.role),
                    rawHex: String(format: "0x%012llX", attr.rawValue),
                    state: state(of: attr, role: info.role)
                )
            }
        }
    }

    /// Same rule as `ATAHealthEvaluator`: value below the threshold = critical; threshold crossed in the
    /// past or bad sectors = needs attention.
    static func state(of attr: ATASmartAttribute, role: ATARole) -> AttributeState {
        if attr.threshold > 0 && attr.current <= attr.threshold { return .critical }
        if attr.threshold > 0 && attr.worst <= attr.threshold { return .warning }
        switch role {
        case .reallocated, .pending, .uncorrectable:
            return attr.rawValue > 0 ? .warning : .normal
        default:
            return .normal
        }
    }

    static func interpretedValue(_ attr: ATASmartAttribute, role: ATARole) -> String {
        switch role {
        case .temperature:
            return attr.value(for: role).map { Formatters.temperature(Int($0)) } ?? "—"
        case .powerOnHours:
            return attr.value(for: role).map(Formatters.hours) ?? "—"
        case .powerCycles, .unsafeShutdowns, .reallocated, .pending, .uncorrectable:
            return attr.value(for: role).map(Formatters.integer) ?? "—"
        case .hostWritesBytes, .hostReadsBytes:
            return attr.value(for: role).map(Formatters.bytes) ?? "—"
        case .lifeRemainingPercentNormalized:
            return L("\(attr.current)\(Formatters.unitSpace)% remaining", "\(attr.current)\(Formatters.unitSpace)% restants")
        case .none:
            return Formatters.integer(attr.rawValue)
        }
    }

    /// The catalog adds “Technical name: …” at the end of the explanation.
    private static func split(_ explanation: String) -> (String, String) {
        guard let range = explanation.range(of: L("\n\nTechnical name: ", "\n\nNom technique : ")) else { return (explanation, "") }
        return (String(explanation[..<range.lowerBound]),
                String(explanation[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Table

/// S.M.A.R.T. table built from plain views (≤ 30 rows). A SwiftUI `Table` (NSTableView) nested
/// in the scrolling page captured the scroll wheel and made scrolling stutter.
struct SmartTableView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk

    var body: some View {
        if let snapshot = disk.snapshot {
            let rows = SmartRows.rows(for: snapshot)
            let isATA: Bool = { if case .ata = snapshot { return true } else { return false } }()
            VStack(alignment: .leading, spacing: 12) {
                header(snapshot)
                VStack(spacing: 0) {
                    SmartHeaderRow(isATA: isATA, showRaw: appManager.showRawValues)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, attr in
                        SmartRow(attr: attr, isATA: isATA, showRaw: appManager.showRawValues)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.2)))
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
        }
    }

    private func header(_ snapshot: DiskHealthSnapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("S.M.A.R.T. attributes", "Attributs S.M.A.R.T."))
                    .font(.headline)
                switch snapshot {
                case .nvme:
                    Text(L("NVMe “SMART / Health Information” log", "Journal NVMe « SMART / Health Information »"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ata(let ata):
                    Text(L("ATA S.M.A.R.T. · normalized values: higher is better, the threshold is set by the manufacturer", "ATA S.M.A.R.T. · valeurs normalisées : plus haut = mieux, le seuil est fixé par le fabricant"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !ata.checksumValid {
                        Label(L("Data not verified (bad checksum)", "Données non vérifiées (somme de contrôle incorrecte)"), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !ata.thresholdsChecksumValid {
                        Label(L("Thresholds not verified (bad checksum)", "Seuils non vérifiés (somme de contrôle incorrecte)"), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Toggle(L("Raw values", "Valeurs brutes"), isOn: $appManager.showRawValues)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(L("Shows raw values in hexadecimal (⌥⌘R)", "Affiche les valeurs brutes en hexadécimal (⌥⌘R)"))
        }
    }
}

private enum SmartColumns {
    static let id: CGFloat = 46
    static let normalized: CGFloat = 52
    static let value: CGFloat = 150
    static let state: CGFloat = 112
}

private struct SmartHeaderRow: View {
    let isATA: Bool
    let showRaw: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("ID").frame(width: SmartColumns.id, alignment: .leading)
            Text(L("Attribute", "Attribut")).frame(maxWidth: .infinity, alignment: .leading)
            if isATA {
                Text(L("Current", "Actuelle")).frame(width: SmartColumns.normalized, alignment: .trailing)
                    .help(L("Current normalized value", "Valeur normalisée actuelle"))
                Text(L("Worst", "Pire")).frame(width: SmartColumns.normalized, alignment: .trailing)
                    .help(L("Lowest normalized value reached", "Plus basse valeur normalisée atteinte"))
                Text(L("Threshold", "Seuil")).frame(width: SmartColumns.normalized, alignment: .trailing)
                    .help(L("Failure threshold set by the manufacturer", "Seuil de défaillance fixé par le fabricant"))
            }
            Text(showRaw ? L("Raw", "Brute") : L("Value", "Valeur")).frame(width: SmartColumns.value, alignment: .trailing)
            Text(L("Status", "État")).frame(width: SmartColumns.state, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct SmartRow: View {
    let attr: UnifiedAttribute
    let isATA: Bool
    let showRaw: Bool
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 10) {
            Text(attr.hexID)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: SmartColumns.id, alignment: .leading)

            HStack(spacing: 5) {
                Text(attr.name)
                    .fontWeight(attr.state.fontWeight)
                    .foregroundStyle(attr.state.tableColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Explanation: \(attr.name)", "Explication : \(attr.name)"))
                .popover(isPresented: $showInfo, arrowEdge: .bottom) { infoPopover }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isATA {
                numeric(attr.current ?? "—", width: SmartColumns.normalized)
                numeric(attr.worst ?? "—", width: SmartColumns.normalized)
                numeric(attr.threshold ?? "—", width: SmartColumns.normalized)
            }

            Text(showRaw ? attr.rawHex : attr.value)
                .font(showRaw ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(showRaw ? .secondary : attr.state.tableColor)
                .fontWeight(showRaw ? .regular : attr.state.fontWeight)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
                .frame(width: SmartColumns.value, alignment: .trailing)

            HStack(spacing: 6) {
                if attr.state != .informational {
                    Circle()
                        .fill(attr.state.dotColor)
                        .frame(width: 7, height: 7)
                }
                Text(attr.state.localizedLabel)
                    .foregroundStyle(attr.state == .informational ? .tertiary : .primary)
            }
            .font(.callout)
            .frame(width: SmartColumns.state, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L("Copy Value", "Copier la valeur")) { copy(attr.value) }
            Button(L("Copy Raw Value", "Copier la valeur brute")) { copy(attr.rawHex) }
            Button(L("Copy Row", "Copier la ligne")) { copy(L("\(attr.hexID) \(attr.name): \(attr.value) (\(attr.rawHex))", "\(attr.hexID) \(attr.name) : \(attr.value) (\(attr.rawHex))")) }
        }
        .accessibilityElement(children: .combine)
    }

    private func numeric(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(attr.name).font(.headline)
            if !attr.technicalName.isEmpty {
                Text(L("Technical name: \(attr.technicalName)", "Nom technique : \(attr.technicalName)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text(attr.explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if attr.value != "—" {
                Text(L("Value: \(attr.value) · raw: \(attr.rawHex)", "Valeur : \(attr.value) · brute : \(attr.rawHex)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
