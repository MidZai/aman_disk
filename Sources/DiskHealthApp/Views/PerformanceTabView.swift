import SwiftUI
import DiskHealthCore
import BenchmarkCore

struct PerformanceTabView: View {
    let disk: RealDisk
    @ObservedObject var appManager: AppManager
    @StateObject private var vm: PerformanceViewModel

    init(disk: RealDisk, appManager: AppManager) {
        self.disk = disk
        self.appManager = appManager
        _vm = StateObject(wrappedValue: PerformanceViewModel(disk: disk, appManager: appManager))
    }

    var body: some View {
        PerformanceContent(disk: disk, vm: vm, benchmark: appManager.benchmark)
            .onAppear { vm.onAppear() }
            .onChange(of: vm.selectedSize) { vm.resolveTargets() }
    }
}

/// Separate so it can observe both the view model and the test in progress.
private struct PerformanceContent: View {
    let disk: RealDisk
    @ObservedObject var vm: PerformanceViewModel
    @ObservedObject var benchmark: BenchmarkController

    private var isRunningHere: Bool { benchmark.runningDiskId == disk.id }
    private var isRunningElsewhere: Bool { benchmark.isRunning && !isRunningHere }

    /// Result shown: test in progress, result picked in the history, or latest result.
    private var displayedResult: BenchmarkResult? {
        vm.viewedResult ?? benchmark.lastResults[disk.id] ?? vm.history.first
    }

    private var gridContent: BenchGridContent {
        if isRunningHere {
            return BenchGridContent(tests: benchmark.liveTests, profile: benchmark.liveProfile, liveState: benchmark.state)
        }
        if let result = displayedResult {
            return BenchGridContent(tests: result.tests, profile: result.profile, liveState: nil)
        }
        return BenchGridContent(tests: [], profile: vm.selectedProfile, liveState: nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsBar
                statusLine
                BenchGridView(content: gridContent, unit: vm.selectedUnit)
                if !isRunningHere, let result = displayedResult {
                    ResultSummary(result: result, isFromHistory: vm.viewedResult != nil) {
                        vm.viewedResult = nil
                    }
                }
                historySection
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $vm.showConfirm) { confirmSheet }
        .onChange(of: benchmark.lastResults[disk.id]?.id) {
            Task { await vm.loadHistory() }
        }
    }

    // MARK: Settings

    private var settingsBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Picker("Volume", selection: $vm.selectedTargetId) {
                if vm.targets.isEmpty {
                    Text(vm.isResolvingTargets ? L("Searching…", "Recherche…") : L("No volume", "Aucun volume")).tag("")
                }
                ForEach(vm.targets) { t in
                    Text(t.label).tag(t.id)
                }
            }
            .frame(maxWidth: 260)
            .help(Strings.benchHelpVolume)
            .disabled(isRunningHere)

            Picker(L("Profile", "Profil"), selection: $vm.selectedProfile) {
                ForEach(BenchProfile.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            .help(Strings.benchHelpProfile)
            .disabled(isRunningHere)

            Picker(L("Size", "Taille"), selection: $vm.selectedSize) {
                ForEach(PerformanceViewModel.sizes, id: \.self) { size in
                    Text("\(size >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio"))").tag(size)
                }
            }
            .fixedSize()
            .help(Strings.benchHelpSize)
            .disabled(isRunningHere)

            Spacer(minLength: 8)

            Picker(L("Unit", "Unité"), selection: $vm.selectedUnit) {
                Text(Formatters.speedUnit).tag(BenchUnit.mbps)
                Text("IOPS").tag(BenchUnit.iops)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if isRunningHere {
                Button(role: .cancel) {
                    benchmark.cancel()
                } label: {
                    Label(L("Stop", "Arrêter"), systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    vm.showConfirm = true
                } label: {
                    Label(L("Run", "Lancer"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canRun || isRunningElsewhere)
                .help(isRunningElsewhere ? L("A test is already running on another drive.", "Un test est déjà en cours sur un autre disque.") : L("Run the performance test", "Lancer le test de performances"))
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if isRunningHere {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(runningText)
                    .monospacedDigit()
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if let reason = vm.selectedTarget?.rejectionReason {
            Label(rejectionText(reason), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            Text(L("Duration: up to \(vm.estimatedDurationText) · data written: up to \(Formatters.bytes(vm.estimatedMaxWritten)) · the test file is deleted at the end.", "Durée : \(vm.estimatedDurationText) au plus · données écrites : \(Formatters.bytes(vm.estimatedMaxWritten)) au plus · le fichier de test est supprimé à la fin."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runningText: String {
        switch benchmark.state {
        case .preparing(let progress)?:
            return L("Creating the test file… \(Int(progress * 100))\(Formatters.unitSpace)%", "Création du fichier de test… \(Int(progress * 100))\(Formatters.unitSpace)%")
        case .pass(let specId, let direction, _, _, _, _)?:
            let label = BenchTestSpec.defaultGrid.first { $0.id == specId }?.label ?? specId
            return "\(direction == .read ? L("Reading", "Lecture") : L("Writing", "Écriture")) \(label)…"
        case .paused(let remaining)?:
            return L("Pause between tests (\(Int(remaining.rounded(.up)))\(Formatters.unitSpace)s)", "Pause entre deux tests (\(Int(remaining.rounded(.up)))\(Formatters.unitSpace)s)")
        default:
            return L("Test running…", "Test en cours…")
        }
    }

    private func rejectionText(_ reason: TargetRejectionReason) -> String {
        let name = vm.selectedTarget?.volume.name ?? L("this volume", "ce volume")
        switch reason {
        case .insufficientFreeSpace:
            return Strings.benchNoSpace(volume: name, size: Formatters.bytes(vm.selectedSize),
                                        required: Formatters.bytes(max(vm.selectedSize.saturatingMultiplied(by: 5), vm.selectedSize + 5 << 30)))
        case .accessDenied:
            return Strings.benchAccessDenied(volume: name)
        default:
            return L("Can't test “\(name)”: \(reason.description.lowercased()).", "Test impossible sur « \(name) » : \(reason.description.lowercased()).")
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        if !vm.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("History", "Historique"))
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(Array(vm.history.prefix(8))) { result in
                        HistoryRow(result: result, isSelected: displayedResult?.id == result.id) {
                            vm.viewedResult = result
                        }
                        if result.id != vm.history.prefix(8).last?.id { Divider() }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
            }
            .disabled(isRunningHere)
        }
    }

    // MARK: Confirmation

    private var confirmSheet: some View {
        let volumeName = vm.selectedTarget?.volume.name ?? "—"
        let message = Strings.benchConfirmMessage(
            volume: volumeName,
            size: "\(vm.selectedSize >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio"))",
            duration: L("up to \(vm.estimatedDurationText)", "\(vm.estimatedDurationText) au plus"),
            maxWritten: Formatters.bytes(vm.estimatedMaxWritten)
        )
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("Run the performance test?", "Lancer le test de performances ?"))
                .font(.headline)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            if disk.physical.isInternal && vm.selectedProfile.includesWrites {
                Text(Strings.benchConfirmInternal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L("Cancel", "Annuler"), role: .cancel) { vm.showConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("Run Test", "Lancer le test")) {
                    vm.showConfirm = false
                    vm.start()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Conditions of the displayed test, and a way back to the latest result when browsing the history.
private struct ResultSummary: View {
    let result: BenchmarkResult
    let isFromHistory: Bool
    let onBackToLatest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !result.completed {
                    Text(stopText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                if isFromHistory {
                    Button(L("Back to Latest Result", "Revenir au dernier résultat"), action: onBackToLatest)
                        .controlSize(.small)
                }
                Button {
                    ExportService.copyBenchmarkSummary(result: result)
                    ToastCenter.shared.show(message: L("Result copied", "Résultat copié"), systemImage: "doc.on.doc")
                } label: {
                    Label(L("Copy", "Copier"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
            Text(ExportService.benchmarkConditions(result))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Strings.benchHelpValues)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var title: String {
        "\(result.profile.label) · \(result.fileSize >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio")) · \(Formatters.date(result.date))"
    }

    private var stopText: String {
        switch result.stopReason {
        case "temperature": return L("Stopped: temperature", "Arrêté : température")
        case "cancelled": return L("Interrupted", "Interrompu")
        default: return L("Failed", "Échec")
        }
    }
}

private struct HistoryRow: View {
    let result: BenchmarkResult
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(Formatters.date(result.date))
                    .frame(minWidth: 150, alignment: .leading)
                Text("\(result.profile.label), \(result.fileSize >> 30)\(Formatters.unitSpace)\(L("GiB", "Gio"))")
                    .foregroundStyle(.secondary)
                Spacer()
                if result.completed {
                    Text(sequentialSummary)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Incomplete", "Incomplet"))
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sequentialSummary: String {
        func speed(_ dir: BenchDirection) -> String? {
            guard let test = result.tests.first(where: { $0.spec.id == "SEQ1M_QD8" && $0.direction == dir }),
                  let best = BenchMath.best(test.passes) else { return nil }
            return Formatters.speed(BenchMath.megabytesPerSecond(bytes: best.bytes, seconds: best.seconds))
        }
        let parts = [speed(.read).map { L("Read \($0)", "Lecture \($0)") }, speed(.write).map { L("Write \($0)", "Écriture \($0)") }].compactMap { $0 }
        return parts.joined(separator: " · ")
    }
}
