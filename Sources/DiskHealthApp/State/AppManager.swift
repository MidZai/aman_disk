import Foundation
import DiskHealthCore

enum SidebarItem: Hashable {
    case physicalDisk(String)
    case volume(String)
}

public struct RealDisk: Identifiable, Equatable, Codable {
    public var id: String { physical.bsdName }
    public let physical: PhysicalDisk
    public let snapshot: DiskHealthSnapshot?
    public let health: HealthAssessment
    public let lastRead: Date
    
    public var smart: NVMeSmartLog? {
        if case .nvme(let sm, _) = snapshot { return sm }
        return nil
    }
    
    public var identify: NVMeIdentify? {
        if case .nvme(_, let id) = snapshot { return id }
        return nil
    }
    
    public var firmware: String? {
        if case .nvme(_, let id) = snapshot { return id.firmwareRevision }
        if case .ata(let ata) = snapshot { return ata.firmware }
        return nil
    }
    
    public var serialNumber: String? {
        if case .nvme(_, let id) = snapshot { return id.serialNumber }
        if case .ata(let ata) = snapshot { return ata.serialNumber }
        return nil
    }
    
    public init(physical: PhysicalDisk, snapshot: DiskHealthSnapshot?, health: HealthAssessment, lastRead: Date = Date()) {
        self.physical = physical
        self.snapshot = snapshot
        self.health = health
        self.lastRead = lastRead
    }
    
    // For backwards compatibility during initialization
    public init(physical: PhysicalDisk, smart: NVMeSmartLog?, identify: NVMeIdentify?, health: HealthAssessment, lastRead: Date = Date()) {
        self.physical = physical
        if let s = smart, let i = identify {
            self.snapshot = .nvme(s, i)
        } else {
            self.snapshot = nil
        }
        self.health = health
        self.lastRead = lastRead
    }
    
    public static func ==(lhs: RealDisk, rhs: RealDisk) -> Bool {
        return lhs.physical == rhs.physical && lhs.lastRead == rhs.lastRead
    }
}

@MainActor
class AppManager: ObservableObject {
    static weak var sharedInstance: AppManager?
    @Published var runningBenchmarkDiskId: String?
    var cancelRunningBenchmark: () -> Void = {}
    @Published var disks: [RealDisk] = []
    @Published var volumes: [Volume] = []
    @Published var needsSudo: Bool = false
    @Published var ignoreSudo: Bool = false
    @Published var isLoading: Bool = true
    @Published var showDetails: Bool = false
    @Published var showRawValues: Bool = false
        @Published var selection: SidebarItem? = nil
    @Published var activeTab: Int = 1
    @Published var requestedVolumeToTest: String? = nil

    private var refreshTimer: Timer?
    private var sampleScheduler: SampleScheduler?
    private var daSession: DASession?
    // P3: Retained opaque pointer used in DiskArbitration callbacks.
    // Balanced by the release in deinit.
    private var daContext: UnsafeMutableRawPointer?
    
        public init() {
        AppManager.sharedInstance = self
        startTimer()
        setupHotplug()
        sampleScheduler = SampleScheduler(appManager: self)
        sampleScheduler?.start()
        LiveStatusController.shared.start(appManager: self)
        Task { @MainActor in loadDisks() }
    }
    
    deinit {
        if let session = daSession {
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        if let ctx = daContext {
            // P3: Release the retained reference established in setupHotplug().
            Unmanaged<AppManager>.fromOpaque(ctx).release()
        }
    }
    
    private func setupHotplug() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.daSession = session
        
        let match = [kDADiskDescriptionVolumeNetworkKey: false] as CFDictionary
        
        let appearCallback: DADiskAppearedCallback = { disk, context in
            if let ctx = context {
                let manager = Unmanaged<AppManager>.fromOpaque(ctx).takeUnretainedValue()
                Task { @MainActor in manager.loadDisks() }
            }
        }
        
        let disappearCallback: DADiskDisappearedCallback = { disk, context in
            if let ctx = context {
                let manager = Unmanaged<AppManager>.fromOpaque(ctx).takeUnretainedValue()
                Task { @MainActor in manager.loadDisks() }
            }
        }
        
        // P3: Use passRetained so the pointer remains valid for the lifetime of the
        // DA callbacks. The retain is balanced by the release in deinit.
        let context = Unmanaged.passRetained(self).toOpaque()
        self.daContext = context
        DARegisterDiskAppearedCallback(session, match, appearCallback, context)
        DARegisterDiskDisappearedCallback(session, match, disappearCallback, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
    
    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadDisks(isAutoRefresh: true) }
        }
    }

    
    private var loadTask: Task<Void, Never>?

    func loadDisks(isAutoRefresh: Bool = false) {
        if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1" {
            self.disks = DemoData.disks.map { 
                RealDisk(physical: $0.physical, snapshot: $0.snapshot, health: $0.health, lastRead: Date()) 
            }
            self.volumes = DemoData.volumes
            self.isLoading = false
            return
        }
        
        if isAutoRefresh {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let bundleId = Bundle.main.bundleIdentifier ?? AppInfo.bundleIdentifier
            let fileURL = appSupport.appendingPathComponent(bundleId).appendingPathComponent("bench-inflight.json")
            if let data = try? Data(contentsOf: fileURL), let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
                return
            }
        }
        
        loadTask?.cancel()
        
        loadTask = Task { [weak self] in
            // Debounce to prevent multiple concurrent IOKit reads when DA triggers multiple events
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            
            if !isAutoRefresh { self.isLoading = true }
            
            let (finalDisks, finalVolumes) = await Task.detached(priority: .userInitiated) {
                let physicalDisks = DiskDiscovery.listPhysicalDisks()
                var newDisks: [RealDisk] = []
                
                for physical in physicalDisks {
                    var currentPhysical = physical
                    var snapshot: DiskHealthSnapshot? = nil
                    var health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Pas d'information S.M.A.R.T. disponible."])
                    
                    if currentPhysical.healthCapability == .supported {
                        do {
                            if currentPhysical.protocolType == .nvme {
                                snapshot = try NVMeBackend.read(bsdName: currentPhysical.bsdName)
                            } else if currentPhysical.protocolType == .ata || currentPhysical.protocolType == .pcieAhci {
                                snapshot = try ATABackend.read(bsdName: currentPhysical.bsdName)
                                NSLog("Successfully read SMART for \(currentPhysical.bsdName)")
                            }
                            
                            if let snap = snapshot {
                                health = Self.evaluate(snap)
                                HistoryStore.shared.record(HistorySample.from(snapshot: snap), for: DiskIdentity.key(for: snap))
                            }
                        } catch let error as ATAReadError where error == .smartDisabled {
                            NSLog("SMART disabled error for \(currentPhysical.bsdName): \(error)")
                            currentPhysical = currentPhysical.withCapability(.unsupported(reason: .smartDisabled))
                        } catch {
                            NSLog("Read failed error for \(currentPhysical.bsdName): \(error)")
                            currentPhysical = currentPhysical.withCapability(.unsupported(reason: .readFailed(code: "\(error)")))
                        }
                    }
                    
                    newDisks.append(RealDisk(physical: currentPhysical, snapshot: snapshot, health: health, lastRead: Date()))
                }
                
                let allVols = VolumeDiscovery.listVolumes()
                return DiskFilter.filter(disks: newDisks, volumes: allVols)
            }.value
            
            guard !Task.isCancelled else { return }
            
            // B7: Back on MainActor — no DispatchQueue needed.
            // Hotplug detection for toasts
            if !self.disks.isEmpty {
                let oldIds = Set(self.disks.map { $0.id })
                let newIds = Set(finalDisks.map { $0.id })
                
                let added = newIds.subtracting(oldIds)
                let removed = oldIds.subtracting(newIds)
                
                for id in added {
                    if let disk = finalDisks.first(where: { $0.id == id }) {
                        ToastCenter.shared.show(message: "\(disk.physical.model) connecté", systemImage: "externaldrive.badge.plus")
                    }
                }
                for id in removed {
                    if let disk = self.disks.first(where: { $0.id == id }) {
                        ToastCenter.shared.show(message: "\(disk.physical.model) déconnecté", systemImage: "externaldrive.badge.minus")
                        
                        if case .physicalDisk(let selId) = self.selection, selId == id {
                            if let internalDisk = finalDisks.first(where: { $0.physical.isInternal }) {
                                self.selection = .physicalDisk(internalDisk.id)
                            } else {
                                self.selection = nil
                            }
                        }
                    }
                }
                
                // Health change detection
                if isAutoRefresh {
                    for newDisk in finalDisks {
                        if let oldDisk = self.disks.first(where: { $0.id == newDisk.id }) {
                            if oldDisk.health.status != newDisk.health.status {
                                let statusStr = newDisk.health.status.localizedLabel
                                ToastCenter.shared.show(message: "L'état de \(newDisk.physical.model) est passé à : \(statusStr)", systemImage: "exclamationmark.triangle")
                            }
                        }
                    }
                }
            }
            
            self.disks = finalDisks
            self.volumes = finalVolumes
            if !isAutoRefresh { self.isLoading = false }
        }
    }

    
    nonisolated static func evaluate(_ snapshot: DiskHealthSnapshot) -> HealthAssessment {
        switch snapshot {
        case .nvme(let smartLog, let identify):
            return HealthEngine.evaluate(smart: smartLog, identify: identify)
        case .ata(let ataSnapshot):
            return ATAHealthEvaluator.evaluate(snapshot: ataSnapshot)
        }
    }
    
    /// Vrai pendant un test de performances : son `TemperatureSampler` prend le relais des mesures.
    var isBenchmarkRunning: Bool {
        if runningBenchmarkDiskId != nil { return true }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? AppInfo.bundleIdentifier
        let fileURL = appSupport.appendingPathComponent(bundleId).appendingPathComponent("bench-inflight.json")
        if let data = try? Data(contentsOf: fileURL), let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            return true
        }
        return false
    }
    
    /// Mesure légère pour la surveillance continue : relit la santé des disques internes déjà
    /// connus (sans nouvelle découverte), enregistre un échantillon et met à jour l'affichage.
    func sampleNow() async {
        if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1" { return }
        let targets = disks.filter { $0.physical.isInternal && $0.physical.healthCapability == .supported && $0.snapshot != nil }
        guard !targets.isEmpty else { return }
        
        let updated: [RealDisk] = await Task.detached(priority: .utility) {
            var result: [RealDisk] = []
            // Une seule lecture à la fois : les disques sont lus l'un après l'autre.
            for disk in targets {
                let snapshot: DiskHealthSnapshot?
                switch disk.physical.protocolType {
                case .nvme: snapshot = try? NVMeBackend.read(bsdName: disk.physical.bsdName)
                case .ata, .pcieAhci: snapshot = try? ATABackend.read(bsdName: disk.physical.bsdName)
                default: snapshot = nil
                }
                guard let snap = snapshot else { continue }
                let now = Date()
                HistoryStore.shared.record(HistorySample.from(snapshot: snap, date: now), for: DiskIdentity.key(for: snap))
                result.append(RealDisk(physical: disk.physical, snapshot: snap, health: AppManager.evaluate(snap), lastRead: now))
            }
            return result
        }.value
        
        guard !updated.isEmpty else { return }
        disks = disks.map { old in updated.first(where: { $0.id == old.id }) ?? old }
    }
    
    /// Disque physique qui porte le volume de démarrage (« / »), sinon le premier disque interne.
    var bootDisk: RealDisk? {
        if let root = volumes.first(where: { $0.mountPoint == "/" }),
           let disk = disks.first(where: { root.physicalDiskBSDNames.contains($0.physical.bsdName) }) {
            return disk
        }
        return disks.first(where: { $0.physical.isInternal && $0.snapshot != nil }) ?? disks.first
    }
    
    func historyKey(for disk: RealDisk) -> String? {
        disk.snapshot.map { DiskIdentity.key(for: $0) }
    }
    
    func isFusionDriveMember(_ disk: RealDisk) -> Bool {
        volumes.contains { $0.physicalDiskBSDNames.count >= 2 && $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
    }
}
