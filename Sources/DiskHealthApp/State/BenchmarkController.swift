import AppKit
import DiskHealthCore
import BenchmarkCore

/// Test de performances en cours. Appartient à `AppManager` (et non à la vue) : changer d'onglet,
/// de disque ou fermer la fenêtre n'interrompt pas le test et ne perd pas son résultat.
@MainActor
final class BenchmarkController: ObservableObject {
    @Published private(set) var runningDiskId: String?
    @Published private(set) var state: BenchmarkState?
    /// Tests terminés du test en cours, affichés dans la grille au fur et à mesure.
    @Published private(set) var liveTests: [TestResult] = []
    @Published private(set) var liveProfile: BenchProfile = .standard
    /// Dernier résultat terminé (par disque), pour l'afficher en revenant sur l'onglet.
    @Published private(set) var lastResults: [String: BenchmarkResult] = [:]

    weak var appManager: AppManager?
    private var runner: BenchmarkRunner?
    private var bridge: DelegateBridge?
    private var terminationPending = false
    private var lastSnapshotApplied: Date = .distantPast

    var isRunning: Bool { runner != nil }

    func start(target: BenchTarget, profile: BenchProfile, fileSize: UInt64, disk: RealDisk) {
        guard runner == nil else { return }
        let r = BenchmarkRunner(target: target, profile: profile, fileSize: fileSize, physicalDisk: disk.physical,
                                diskKey: disk.benchmarkKey, appVersion: AppInfo.version)
        let diskId = disk.id
        r.onTemperatureSnapshot = { [weak self] snapshot, date in
            HistoryStore.shared.record(HistorySample.from(snapshot: snapshot, date: date), for: DiskIdentity.key(for: snapshot))
            Task { @MainActor in self?.applySnapshot(snapshot, date: date, diskId: diskId) }
        }
        let bridge = DelegateBridge(owner: self)
        r.delegate = bridge
        self.bridge = bridge
        runner = r
        runningDiskId = diskId
        liveProfile = profile
        liveTests = []
        state = .preparing(progress: 0)
        lastResults[diskId] = nil
        r.start()
    }

    func cancel() {
        runner?.cancel()
    }

    /// Quitter pendant un test : l'app attend la suppression du fichier de test avant de se fermer.
    func cancelForTermination() {
        terminationPending = true
        runner?.cancel()
        // Filet de sécurité : ne jamais bloquer la fermeture plus de 5 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.terminationPending else { return }
            self.terminationPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func applySnapshot(_ snapshot: DiskHealthSnapshot, date: Date, diskId: String) {
        // Relevé toutes les 2 s pendant le test ; l'interface n'a pas besoin de plus d'un toutes les 15 s.
        guard date.timeIntervalSince(lastSnapshotApplied) >= 15 else { return }
        lastSnapshotApplied = date
        appManager?.recordBenchmarkSnapshot(snapshot, date: date, diskId: diskId)
    }

    fileprivate func didUpdate(_ newState: BenchmarkState) {
        guard runner != nil else { return }
        state = newState
    }

    fileprivate func didComplete(_ test: TestResult) {
        liveTests.append(test)
    }

    fileprivate func didFinish(_ result: BenchmarkResult) {
        let diskId = runningDiskId
        runner = nil
        bridge = nil
        runningDiskId = nil
        state = nil
        liveTests = []
        if let diskId { lastResults[diskId] = result }
        BenchmarkHistoryManager.shared.save(result)

        if terminationPending {
            terminationPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        switch result.stopReason {
        case nil:
            ToastCenter.shared.show(message: L("Performance test finished", "Test de performances terminé"), systemImage: "checkmark.circle")
        case "temperature":
            let temp = result.conditions.temperatureMaxC.map(String.init) ?? "\(BenchmarkRunner.temperatureLimitC)"
            ToastCenter.shared.show(message: Strings.benchStoppedTemp(temp: temp), systemImage: "thermometer.high")
        case "cancelled":
            ToastCenter.shared.show(message: Strings.benchCancelled, systemImage: "xmark.circle")
        default:
            ToastCenter.shared.show(message: L("The test failed. The test file was deleted.", "Le test a échoué. Le fichier de test a été supprimé."), systemImage: "exclamationmark.triangle")
        }
    }
}

/// Le coureur appelle son délégué sur le fil principal ; ce pont le relaie à l'acteur principal.
private final class DelegateBridge: BenchmarkRunnerDelegate {
    weak var owner: BenchmarkController?
    init(owner: BenchmarkController) { self.owner = owner }

    func benchmarkDidUpdateState(_ state: BenchmarkState) {
        MainActor.assumeIsolated { owner?.didUpdate(state) }
    }
    func benchmarkDidComplete(test: TestResult) {
        MainActor.assumeIsolated { owner?.didComplete(test) }
    }
    func benchmarkDidFinish(result: BenchmarkResult) {
        MainActor.assumeIsolated { owner?.didFinish(result) }
    }
}
