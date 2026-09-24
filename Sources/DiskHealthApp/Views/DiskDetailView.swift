import SwiftUI
import DiskHealthCore

struct DiskDetailView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DiskHeaderView(disk: disk, isFusionMember: appManager.isFusionDriveMember(disk))

                if appManager.smartNotices[disk.id] == .enabled {
                    SmartEnabledCard { appManager.dismissSmartNotice(for: disk.id) }
                }

                if disk.health.status != .good && disk.health.status != .unknown {
                    ReasonsCallout(health: disk.health)
                }

                if let metrics = disk.metrics {
                    StatTilesGrid(disk: disk, metrics: metrics)
                }

                TemperatureHistoryView(historyKey: disk.historyKey, lastRead: disk.lastRead)

                SmartTableView(disk: disk)

                DiskEventsView(historyKey: disk.historyKey, lastRead: disk.lastRead)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Header

private struct DiskHeaderView: View {
    let disk: RealDisk
    let isFusionMember: Bool
    @State private var showSerial = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                identity
                Spacer(minLength: 12)
                infoGrid
            }
            VStack(alignment: .leading, spacing: 16) {
                identity
                infoGrid
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 18) {
            HealthRingView(health: disk.health, capability: disk.physical.healthCapability)
                .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 5) {
                Text(disk.physical.model)
                    .font(.title2.bold())
                    .textSelection(.enabled)

                Label {
                    Text(disk.health.status.localizedLabel)
                } icon: {
                    Image(systemName: disk.health.status.symbolName)
                        .foregroundStyle(disk.health.status.color)
                }
                .font(.headline)

                Text(lifeText)
                    .font(.callout)
                    .foregroundStyle(lifeColor)
                    .monospacedDigit()

                Text(subtext)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
            GridRow {
                InfoPair(label: L("Capacity", "Capacité"), value: Formatters.bytes(disk.physical.sizeBytes))
                InfoPair(label: "Firmware", value: disk.firmware ?? "—")
            }
            GridRow {
                InfoPair(label: "Interface", value: disk.physical.interfaceLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Serial number", "N° de série"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(showSerial ? (disk.serialNumber ?? "—") : SerialMasking.masked(disk.serialNumber))
                            .font(.body.weight(.medium))
                            .textSelection(.enabled)
                        if disk.serialNumber != nil {
                            Button {
                                showSerial.toggle()
                            } label: {
                                Image(systemName: showSerial ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(showSerial ? L("Hide serial number", "Masquer le numéro de série") : L("Show serial number", "Afficher le numéro de série"))
                            .accessibilityLabel(showSerial ? L("Hide serial number", "Masquer le numéro de série") : L("Show serial number", "Afficher le numéro de série"))
                        }
                    }
                }
            }
            GridRow {
                InfoPair(label: L("Location", "Emplacement"), value: disk.physical.locationLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Last read", "Dernière lecture"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LastReadLabel(date: disk.lastRead)
                        // Fixed-size frame: the text changes every second, but its size doesn't propagate
                        // up to the page. Without it, every second triggered a layout pass of the whole
                        // window (chart included): ~5% CPU all the time.
                        .frame(width: 110, height: 20, alignment: .leading)
                }
            }
        }
        .fixedSize()
    }

    private var lifeText: String {
        guard let life = disk.knownLifePercent else {
            return L("Remaining life: not reported by this drive", "Durée de vie restante : non fournie par ce disque")
        }
        return L("Remaining life: \(life)\(Formatters.unitSpace)%", "Durée de vie restante : \(life)\(Formatters.unitSpace)%")
    }

    private var lifeColor: Color {
        guard disk.knownLifePercent != nil else { return .secondary }
        switch AmanPalette.level(health: disk.health, capability: disk.physical.healthCapability) {
        case .water: return .primary
        case .orange: return .orange
        case .red: return .red
        }
    }

    private var subtext: String {
        var parts = [disk.physical.mediumAndLocationLabel, disk.physical.interfaceLabel]
        if case .ata(let ata)? = disk.snapshot, disk.physical.mediumType == .rotational, ata.rotationRate > 1 {
            parts.append(L("\(Formatters.integer(ata.rotationRate))\(Formatters.unitSpace)\(L("rpm", "tr/min"))", "\(Formatters.integer(ata.rotationRate))\(Formatters.unitSpace)tr/min"))
        }
        if isFusionMember {
            parts.append(Strings.fusionDriveMember)
        }
        return parts.joined(separator: " · ")
    }
}

/// “12 s ago”: every second when the window is in the foreground, every 10 s otherwise.
private struct LastReadLabel: View {
    let date: Date
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.periodic(from: date, by: activeState == .key ? 1 : 10)) { context in
            label(now: context.date)
        }
    }

    private func label(now: Date) -> some View {
        Text(Formatters.age(since: date, now: now))
            .font(.body.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// All the reasons for a degraded status, not just the first one truncated to 60 characters.
private struct ReasonsCallout: View {
    let health: HealthAssessment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: health.status.symbolName)
                .font(.title3)
                .foregroundStyle(health.status.color)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(health.reasons, id: \.self) { reason in
                    Text(reason)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(health.status == .bad
                     ? L("Back up your data now.", "Sauvegardez vos données dès maintenant.")
                     : L("Make sure your backups are up to date.", "Pensez à vérifier que vos sauvegardes sont à jour."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(health.status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(health.status.color.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }
}

/// Shown once, after S.M.A.R.T. was turned on automatically or manually.
private struct SmartEnabledCard: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text(Strings.smartEnabledNotice)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Close", "Fermer"))
            .accessibilityLabel(L("Close", "Fermer"))
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.green.opacity(0.3)))
    }
}

/// Drive log: only appears if it contains at least one event.
private struct DiskEventsView: View {
    let historyKey: String?
    let lastRead: Date
    @State private var events: [DiskEvent] = []

    var body: some View {
        Group {
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Log", "Journal"))
                        .font(.headline)
                    ForEach(events.reversed(), id: \.self) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(Self.label(event.kind))
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .task(id: "\(historyKey ?? "")|\(lastRead.timeIntervalSince1970)") {
            events = historyKey.map { DiskEventLog.shared.events(for: $0) } ?? []
        }
    }

    private static func label(_ kind: DiskEvent.Kind) -> String {
        switch kind {
        case .smartEnabled: return L("S.M.A.R.T. was off; Aman Disk turned it on.", "S.M.A.R.T. était désactivé ; Aman l'a activé.")
        }
    }
}

struct InfoPair: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
        }
    }
}

/// Masked serial number, the same way everywhere: “••••1234”.
enum SerialMasking {
    static func masked(_ serial: String?) -> String {
        guard let serial, !serial.isEmpty else { return "—" }
        guard serial.count > 4 else { return "••••" }
        return "••••\(serial.suffix(4))"
    }
}
