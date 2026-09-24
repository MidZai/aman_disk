import SwiftUI
import Charts
import AppKit
import DiskHealthCore

/// Label of the menu bar item: *template* ring and, optionally, the temperature.
struct MenuBarLabel: View {
    @ObservedObject var appManager: AppManager
    @AppStorage(PreferenceKey.showMenuBarTemperature) private var showTemperature = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let boot = appManager.bootDisk
        let fraction = boot.map { AmanPalette.fraction(health: $0.health, capability: $0.physical.healthCapability) } ?? 1
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIconRenderer.cachedImage(fraction: fraction))
            if showTemperature, let t = boot?.temperatureC {
                Text("\(t)°")
                    .monospacedDigit()
            }
        }
        .onAppear {
            // Always present: used to reopen the window from a notification.
            WindowOpener.openMain = { [openWindow] in openWindow(id: AppScene.mainWindowID) }
        }
    }
}

/// Menu bar panel (320 pt).
struct MenuBarPanel: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var bootSamples: [HistorySample] = []

    private var internalDisks: [RealDisk] {
        appManager.disks.filter { $0.physical.isInternal }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aman Disk")
                .font(.headline)

            if internalDisks.isEmpty || appManager.isLoading {
                Text(appManager.isLoading ? L("Reading drives…", "Lecture des disques…") : L("No internal drive found", "Aucun disque interne détecté"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(internalDisks) { disk in
                        diskRow(disk)
                    }
                }
            }

            if let boot = appManager.bootDisk, boot.snapshot != nil {
                Divider()
                miniChart(boot: boot)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton(L("Open Aman Disk", "Ouvrir Aman Disk")) {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: AppScene.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton(L("Settings…", "Réglages…")) {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider().padding(.vertical, 2)
                menuButton(L("Quit Aman Disk", "Quitter Aman Disk")) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .task(id: appManager.bootDisk?.lastRead) { await loadBootHistory() }
    }

    private func diskRow(_ disk: RealDisk) -> some View {
        HStack(spacing: 10) {
            MiniRingView(health: disk.health, capability: disk.physical.healthCapability, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(disk.physical.model)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(disk.health.status.localizedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                if let t = disk.temperatureC {
                    Text(Formatters.temperature(t))
                        .font(.callout)
                        .monospacedDigit()
                }
                if let pct = disk.knownLifePercent {
                    Text(L("\(pct)\(Formatters.unitSpace)% life", "\(pct)\(Formatters.unitSpace)% de vie"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func miniChart(boot: RealDisk) -> some View {
        let agg = HistoryAggregation.aggregate(samples: bootSamples, range: .oneHour)
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Temperature — last hour", "Température — dernière heure"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if agg.points.count < 2 {
                Text(L("Not enough measurements yet.", "Pas encore assez de mesures."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart(agg.points) { point in
                    LineMark(
                        x: .value("Heure", point.date),
                        y: .value("Temp", point.temperature),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: Double(max(0, (agg.min ?? 0) - 3))...Double((agg.max ?? 0) + 3))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))°") }
                        }
                    }
                }
                .frame(height: 60)
                .accessibilityLabel(L("Temperature over the last hour", "Température de la dernière heure"))
                .accessibilityValue(TemperatureHistoryView.legendText(agg))
            }
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        MenuRowButton(title: title, action: action)
    }

    private func loadBootHistory() async {
        guard let key = appManager.bootDisk?.historyKey else {
            bootSamples = []
            return
        }
        bootSamples = await HistoryStore.shared.loadSamples(for: key, since: Date().addingTimeInterval(-3600))
    }
}

/// Full-width button styled like a menu item, highlighted on hover.
private struct MenuRowButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.accentColor.opacity(0.85) : Color.clear)
                )
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
