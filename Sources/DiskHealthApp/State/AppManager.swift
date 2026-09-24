import Foundation
import DiskArbitration
import DiskHealthCore

enum SidebarItem: Hashable {
    case physicalDisk(String)
    case volume(String)
}

enum DetailTab: Hashable {
    case health, performance
}

/// Suite d'une activation de S.M.A.R.T., affichée sur la page du disque.
enum SmartNotice: Equatable {
    case enabled
    case failed(code: Int32)
}

/// Un disque physique et son dernier relevé.
public struct RealDisk: Identifiable, Equatable {
    public var id: String { physical.bsdName }
    public let physical: PhysicalDisk
    public let snapshot: DiskHealthSnapshot?
    public let health: HealthAssessment
    public let lastRead: Date
    /// Indicateurs extraits une seule fois par relevé (et non à chaque rendu).
    public let metrics: DiskMetrics?
    /// Clé stable (modèle + numéro de série) de l'historique et des résultats de test.
    /// Le nom BSD (`disk0`) peut changer d'un démarrage à l'autre : il ne sert pas de clé.
    public let historyKey: String?

    public init(physical: PhysicalDisk, snapshot: DiskHealthSnapshot?, health: HealthAssessment, lastRead: Date = Date()) {
        self.physical = physical
        self.snapshot = snapshot
        self.health = health
        self.lastRead = lastRead
        self.metrics = snapshot.map(DiskMetrics.init(snapshot:))
        self.historyKey = snapshot.map { DiskIdentity.key(for: $0) }
    }

    public var identify: NVMeIdentify? {
        if case .nvme(_, let id) = snapshot { return id }
        return nil
    }

    public var firmware: String? {
        switch snapshot {
        case .nvme(_, let id): return id.firmwareRevision
        case .ata(let ata): return ata.firmware
        case nil: return nil
        }
    }

    public var serialNumber: String? {
        switch snapshot {
        case .nvme(_, let id): return id.serialNumber
        case .ata(let ata): return ata.serialNumber
        case nil: return nil
        }
    }

    public var temperatureC: Int? { metrics?.temperatureC }

    /// Clé des résultats de test de performances.
    var benchmarkKey: String {
        historyKey ?? DiskIdentity.key(model: physical.model, serial: "")
    }

    /// Pourcentage de durée de vie affichable, uniquement s'il est fourni par le disque.
    var knownLifePercent: Int? {
        AmanPalette.knownPercent(health: health, capability: physical.healthCapability)
    }
}

@MainActor
final class AppManager: ObservableObject {
    static weak var sharedInstance: AppManager?
    static let isDemo = ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1"

    @Published private(set) var disks: [RealDisk] = []
    @Published private(set) var volumes: [Volume] = []
    /// Premier chargement seulement : les actualisations suivantes gardent la page affichée.
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published var showDetails = false
    @Published var showRawValues = false
    @Published var selection: SidebarItem?
    @Published var activeTab: DetailTab = .health
    @Published var requestedVolumeToTest: String?
    /// Par identifiant de disque. « Activé » reste affiché jusqu'à ce que l'utilisateur le ferme.
    @Published private(set) var smartNotices: [String: SmartNotice] = [:]
    @Published private(set) var enablingSmart: Set<String> = []
    /// Fenêtre principale ouverte. Fermée (mode barre des menus), SwiftUI garde sa hiérarchie de
    /// vues en vie et continue de la mettre à jour : son contenu est alors remplacé par une vue vide.
    @Published var isMainWindowVisible = true

    /// Vit aussi longtemps que l'app : changer d'onglet ou de disque n'interrompt pas un test.
    let benchmark = BenchmarkController()

    private var refreshTimer: Timer?
    private var sampleScheduler: SampleScheduler?
    private var daSession: DASession?
    private var loadTask: Task<Void, Never>?
    nonisolated static let smartMemory = UserDefaultsActivationMemory()

    init() {
        AppManager.sharedInstance = self
        benchmark.appManager = self
        startTimer()
        if !Self.isDemo {
            setupHotplug()
        }
        sampleScheduler = SampleScheduler(appManager: self)
        sampleScheduler?.start()
        LiveStatusController.shared.start(appManager: self)
        loadDisks()
    }

    private func setupHotplug() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        daSession = session

        // Seuls les disques entiers nous intéressent : les apparitions de volumes, d'images disque
        // montées ou de partitions ne relancent pas une découverte complète.
        let match = [kDADiskDescriptionMediaWholeKey as String: true] as CFDictionary
        let callback: DADiskAppearedCallback = { _, context in
            guard let context else { return }
            let manager = Unmanaged<AppManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in manager.loadDisks() }
        }
        // AppManager vit aussi longtemps que l'app : une référence non retenue suffit.
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, match, callback, context)
        DARegisterDiskDisappearedCallback(session, match, callback, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func startTimer() {
        // Découverte complète toutes les 5 min (espace libre des volumes) ; la santé, elle,
        // est relue toutes les 30 s par SampleScheduler.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadDisks(isAutoRefresh: true) }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func loadDisks(isAutoRefresh: Bool = false) {
        if Self.isDemo {
            disks = DemoData.disks.map {
                RealDisk(physical: $0.physical, snapshot: $0.snapshot, health: $0.health, lastRead: Date())
            }
            volumes = DemoData.volumes
            isLoading = false
            return
        }
        // Pendant un test, la file du disque est saturée : on ne rajoute pas de lectures.
        if isAutoRefresh && benchmark.isRunning { return }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            // Regroupe les rafales d'événements DiskArbitration (branchement, démarrage).
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }

            let knownIdentify = self.knownIdentifies()
            let (finalDisks, finalVolumes, results) = await Task.detached(priority: .userInitiated) {
                // Filtre avant toute lecture S.M.A.R.T. : les disques externes, images disque et
                // disques virtuels ne sont pas affichés, inutile de les interroger.
                let physicalDisks = DiskDiscovery.listPhysicalDisks().filter(DiskFilter.isMonitored)
                let results = physicalDisks.map { Self.read($0, knownIdentify: knownIdentify[$0.bsdName]) }
                let (disks, volumes) = DiskFilter.filter(disks: results.map(\.disk), volumes: VolumeDiscovery.listVolumes())
                return (disks, volumes, results)
            }.value

            guard !Task.isCancelled else { return }
            self.apply(disks: finalDisks, announceChanges: !self.disks.isEmpty)
            self.updateSmartNotices(results)
            self.volumes = finalVolumes
            self.isLoading = false
        }
    }

    /// Lecture complète d'un disque (hors fil principal). En ATA, S.M.A.R.T. désactivé est activé
    /// une seule fois par disque si le réglage le permet (voir `SmartActivator`).
    nonisolated private static func read(_ physical: PhysicalDisk, knownIdentify: NVMeIdentify?) -> (disk: RealDisk, notice: SmartNotice?) {
        var current = physical
        var snapshot: DiskHealthSnapshot?
        var notice: SmartNotice?
        var health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: [L("No S.M.A.R.T. information available.", "Pas d'information S.M.A.R.T. disponible.")])
        if physical.healthCapability == .supported {
            do {
                switch physical.protocolType {
                case .nvme: snapshot = try NVMeBackend.read(bsdName: physical.bsdName, knownIdentify: knownIdentify)
                case .ata, .pcieAhci:
                    let autoEnable = UserDefaults.standard.object(forKey: PreferenceKey.autoEnableSmart) as? Bool ?? true
                    let result = try SmartActivator(memory: smartMemory).read(bsdName: physical.bsdName, autoEnable: autoEnable)
                    (snapshot, notice) = handle(result)
                    if snapshot == nil { current = physical.withCapability(.unsupported(reason: .smartDisabled)) }
                default: break
                }
                if let snap = snapshot {
                    health = evaluate(snap)
                    HistoryStore.shared.record(HistorySample.from(snapshot: snap), for: DiskIdentity.key(for: snap))
                }
            } catch ATAReadError.smartDisabled {
                current = physical.withCapability(.unsupported(reason: .smartDisabled))
            } catch {
                NSLog("Aman Disk : lecture S.M.A.R.T. impossible pour %@ (%@)", physical.bsdName, "\(error)")
                current = physical.withCapability(.unsupported(reason: .readFailed(code: "\(error)")))
            }
        }
        return (RealDisk(physical: current, snapshot: snapshot, health: health, lastRead: Date()), notice)
    }

    /// Relevé obtenu et message à afficher ; l'activation réussie entre dans le journal du disque.
    nonisolated private static func handle(_ result: SmartActivationResult) -> (DiskHealthSnapshot?, SmartNotice?) {
        switch result {
        case .read(let snapshot):
            return (snapshot, nil)
        case .enabled(let snapshot):
            DiskEventLog.shared.append(DiskEvent(kind: .smartEnabled), for: DiskIdentity.key(for: snapshot))
            return (snapshot, .enabled)
        case .disabled:
            return (nil, nil)
        case .enableFailed(let code):
            return (nil, .failed(code: code))
        }
    }

    private func updateSmartNotices(_ results: [(disk: RealDisk, notice: SmartNotice?)]) {
        for (disk, notice) in results {
            if let notice {
                smartNotices[disk.id] = notice
            } else if case .failed? = smartNotices[disk.id], disk.physical.healthCapability == .supported {
                smartNotices[disk.id] = nil
            }
        }
    }

    func dismissSmartNotice(for diskId: String) {
        smartNotices[diskId] = nil
    }

    /// Activation demandée par l'utilisateur (« Activer S.M.A.R.T.… » ou « Réessayer »).
    func enableSmart(diskId: String) {
        guard !Self.isDemo, let disk = disk(withId: diskId), !enablingSmart.contains(diskId) else { return }
        enablingSmart.insert(diskId)
        let bsdName = disk.physical.bsdName
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (DiskHealthSnapshot?, SmartNotice?) in
                do {
                    return AppManager.handle(try SmartActivator(memory: AppManager.smartMemory).enable(bsdName: bsdName))
                } catch {
                    // Activé, mais la relecture a échoué : la prochaine découverte s'en chargera.
                    return (nil, nil)
                }
            }.value
            enablingSmart.remove(diskId)
            smartNotices[diskId] = outcome.1
            guard let snapshot = outcome.0, let index = disks.firstIndex(where: { $0.id == diskId }) else {
                if outcome.1 == nil { loadDisks() }
                return
            }
            HistoryStore.shared.record(HistorySample.from(snapshot: snapshot), for: DiskIdentity.key(for: snapshot))
            var newDisks = disks
            newDisks[index] = RealDisk(physical: disks[index].physical.withCapability(.supported), snapshot: snapshot, health: Self.evaluate(snapshot))
            apply(disks: newDisks, announceChanges: false)
        }
    }

    private func knownIdentifies() -> [String: NVMeIdentify] {
        var result: [String: NVMeIdentify] = [:]
        for disk in disks { if let id = disk.identify { result[disk.id] = id } }
        return result
    }

    /// Publie la nouvelle liste et signale les branchements et changements d'état.
    private func apply(disks newDisks: [RealDisk], announceChanges: Bool) {
        if announceChanges {
            let oldById = Dictionary(disks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let newIds = Set(newDisks.map(\.id))
            for disk in newDisks where oldById[disk.id] == nil {
                ToastCenter.shared.show(message: L("\(disk.physical.model) connected", "\(disk.physical.model) connecté"), systemImage: "externaldrive.badge.plus")
            }
            for (id, disk) in oldById where !newIds.contains(id) {
                ToastCenter.shared.show(message: L("\(disk.physical.model) disconnected", "\(disk.physical.model) déconnecté"), systemImage: "externaldrive.badge.minus")
                if selection == .physicalDisk(id) {
                    selection = newDisks.first(where: { $0.physical.isInternal }).map { .physicalDisk($0.id) }
                }
            }
            for disk in newDisks {
                if let old = oldById[disk.id], old.snapshot != nil, disk.snapshot != nil, old.health.status != disk.health.status {
                    ToastCenter.shared.show(message: L("\(disk.physical.model): \(disk.health.status.localizedLabel)", "\(disk.physical.model) : \(disk.health.status.localizedLabel)"), systemImage: disk.health.status.symbolName)
                }
            }
        }
        disks = newDisks
    }

    nonisolated static func evaluate(_ snapshot: DiskHealthSnapshot) -> HealthAssessment {
        switch snapshot {
        case .nvme(let smartLog, let identify):
            return HealthEngine.evaluate(smart: smartLog, identify: identify)
        case .ata(let ataSnapshot):
            return ATAHealthEvaluator.evaluate(snapshot: ataSnapshot)
        }
    }

    /// Vrai pendant un test de performances : son échantillonneur prend le relais des mesures.
    var isBenchmarkRunning: Bool { benchmark.isRunning }

    /// Mesure légère pour la surveillance continue : relit la santé des disques internes déjà
    /// connus (sans nouvelle découverte), enregistre un échantillon et met à jour l'affichage.
    func sampleNow() async {
        if Self.isDemo { return }
        let targets = disks.filter { $0.physical.isInternal && $0.physical.healthCapability == .supported && $0.snapshot != nil }
        guard !targets.isEmpty else { return }

        let updated: [RealDisk] = await Task.detached(priority: .utility) {
            // Une seule lecture à la fois : les disques sont lus l'un après l'autre.
            // En NVMe, seules les 512 octets du journal SMART sont relus (Identify ne change pas).
            targets.compactMap { disk -> RealDisk? in
                let snapshot: DiskHealthSnapshot?
                switch disk.physical.protocolType {
                case .nvme: snapshot = try? NVMeBackend.read(bsdName: disk.physical.bsdName, knownIdentify: disk.identify)
                case .ata, .pcieAhci: snapshot = try? ATABackend.read(bsdName: disk.physical.bsdName)
                default: snapshot = nil
                }
                guard let snap = snapshot else { return nil }
                let now = Date()
                HistoryStore.shared.record(HistorySample.from(snapshot: snap, date: now), for: DiskIdentity.key(for: snap))
                return RealDisk(physical: disk.physical, snapshot: snap, health: AppManager.evaluate(snap), lastRead: now)
            }
        }.value

        guard !updated.isEmpty else { return }
        var newDisks = disks
        for disk in updated {
            if let index = newDisks.firstIndex(where: { $0.id == disk.id }) { newDisks[index] = disk }
        }
        apply(disks: newDisks, announceChanges: true)
    }

    /// Relevé pris par le test de performances : garde l'historique et l'affichage à jour.
    func recordBenchmarkSnapshot(_ snapshot: DiskHealthSnapshot, date: Date, diskId: String) {
        guard let index = disks.firstIndex(where: { $0.id == diskId }) else { return }
        var newDisks = disks
        newDisks[index] = RealDisk(physical: disks[index].physical, snapshot: snapshot, health: Self.evaluate(snapshot), lastRead: date)
        apply(disks: newDisks, announceChanges: true)
    }

    /// Disque physique qui porte le volume de démarrage (« / »), sinon le premier disque interne.
    var bootDisk: RealDisk? {
        if let root = volumes.first(where: { $0.mountPoint == "/" }),
           let disk = disks.first(where: { root.physicalDiskBSDNames.contains($0.physical.bsdName) }) {
            return disk
        }
        return disks.first(where: { $0.physical.isInternal && $0.snapshot != nil }) ?? disks.first
    }

    func disk(withId id: String) -> RealDisk? {
        disks.first { $0.id == id }
    }

    var selectedDisk: RealDisk? {
        if case .physicalDisk(let id) = selection { return disk(withId: id) }
        return nil
    }

    func volumes(on disk: RealDisk) -> [Volume] {
        volumes.filter { $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
    }

    func isFusionDriveMember(_ disk: RealDisk) -> Bool {
        volumes.contains { $0.physicalDiskBSDNames.count >= 2 && $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
    }
}
