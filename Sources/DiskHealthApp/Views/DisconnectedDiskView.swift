import SwiftUI
import DiskHealthCore
import BenchmarkCore

/// View displayed when a disconnected external drive is selected.
struct DisconnectedDiskView: View {
    let item: DisconnectedDisk
    @ObservedObject var appManager: AppManager
    @State private var benchmarkHistory: [BenchmarkResult] = []
    @State private var selectedResult: BenchmarkResult?

    private var disk: RealDisk { item.disk }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerCard

                // Performance history if available
                if !benchmarkHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Performance history", "Historique des performances"))
                            .font(.headline)

                        if let result = selectedResult ?? benchmarkHistory.first {
                            BenchGridView(content: BenchGridContent(tests: result.tests, profile: result.profile, liveState: nil), unit: .mbps)
                            HStack {
                                Text("\(result.profile.label) · \(result.fileSize >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio")) · \(Formatters.date(result.date))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    ExportService.copyBenchmarkSummary(result: result)
                                    ToastCenter.shared.show(message: L("Result copied", "Résultat copié"), systemImage: "doc.on.doc")
                                } label: {
                                    Label(L("Copy", "Copier"), systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                            }
                        }

                        if benchmarkHistory.count > 1 {
                            VStack(spacing: 0) {
                                ForEach(Array(benchmarkHistory.prefix(8))) { res in
                                    Button {
                                        selectedResult = res
                                    } label: {
                                        HStack {
                                            Text(res.profile.label)
                                                .font(.callout.weight(.medium))
                                            Text("\(res.fileSize >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio"))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(Formatters.date(res.date))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if res.id != benchmarkHistory.prefix(8).last?.id { Divider() }
                                }
                            }
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
                        }
                    }
                }

                // Drive information
                driveInfoCard
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: item.id) {
            benchmarkHistory = await BenchmarkHistoryManager.shared.loadResults(for: disk)
            selectedResult = benchmarkHistory.first
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "externaldrive.badge.xmark").accessibilityHidden(true)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(disk.physical.model)
                        .font(.title2.weight(.bold))
                        .environment(\.layoutDirection, .leftToRight)

                    Text(L("Disconnected", "Déconnecté"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Text(Strings.lastSeen(date: Formatters.date(item.lastSeen)))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Text(L("Reconnect this drive to run a performance test or update its health status.",
                       "Rebranchez ce disque pour relancer un test de performances ou actualiser son état."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
    }

    private var driveInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.driveInformation)
                .font(.headline)

            VStack(spacing: 6) {
                infoRow(L("Capacity", "Capacité"), Formatters.bytes(disk.physical.sizeBytes))
                infoRow(L("Connection", "Connexion"), disk.physical.detailInterfaceLabel)
                if let chip = disk.physical.usbBridgeLabel {
                    infoRow(Strings.bridgeChip, chip)
                }
                if let speed = disk.physical.usbLinkSpeedLabel {
                    infoRow(Strings.linkSpeed, speed)
                }
                if let proto = disk.physical.usbProtocolLabel {
                    infoRow(Strings.protocolLabel, proto)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(.callout)
    }
}
