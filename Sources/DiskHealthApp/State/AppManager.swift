import Foundation
import AppKit
import DiskArbitration
import DiskHealthCore
import BenchmarkCore

enum SidebarItem: Hashable {
    case physicalDisk(String)
    case volume(String)
    case disconnectedDisk(String)
}

enum DetailTab: Hashable {
    case health, performance
}

/// Outcome of turning on S.M.A.R.T., shown on the drive's page.
enum SmartNotice: Equatable {
    case enabled
    case failed(code: Int32)
}

/// Information about an external drive that is currently disconnected.
public struct DisconnectedDisk: Identifiable, Equatable {
    public var id: String { disk.benchmarkKey }
    public let disk: RealDisk
    public let lastSeen: Date

    public init(disk: RealDisk, lastSeen: Date = Date()) {
        self.disk = disk
        self.lastSeen = lastSeen
    }
}

/// A physical drive and its latest reading.
public struct RealDisk: Identifiable, Equatable {
    public var id: String { physical.bsdName }
    public let physical: PhysicalDisk
    public let snapshot: DiskHealthSnapshot?
    public let health: HealthAssessment
    public let lastRead: Date
    /// Indicators extracted once per reading (not on every render).
    public let metrics: DiskMetrics?
    /// Stable key (model + serial number) for the history and the test results.
    /// The BSD name (`disk0`) can change from one boot to the next: it isn't used as a key.
    public let historyKey: String?

    public init(physical: PhysicalDisk, snapshot: DiskHealthSnapshot?, health: HealthAssessment, lastRead: Date = Date()) {
        self.physical = physical
        self.snapshot = snapshot
        self.health = health
        self.lastRead = lastRead
        self.metrics = snapshot.map(DiskMetrics.init(snapshot:))
        self.historyKey = snapshot.map { DiskIdentity.key(for: $0) }
            ?? physical.serialNumber.flatMap { $0.isEmpty ? nil : DiskIdentity.key(model: physical.model, serial: $0) }
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
        case nil: return physical.serialNumber
        }
    }

    public var temperatureC: Int? { metrics?.temperatureC }

    /// Key for the performance test results.
    var benchmarkKey: String {
        historyKey ?? DiskIdentity.key(model: physical.model, serial: physical.serialNumber ?? "")
    }

    /// Life percentage that can be shown, only if the drive reports it.
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
    @Published private(set) var disconnectedDisks: [DisconnectedDisk] = []
    private var externalDisksHistory: [String: (disk: RealDisk, lastSeen: Date)] = [:]
    /// First load only: later refreshes keep the page on screen.
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published var showDetails = false
    @Published var showRawValues = false
    @Published var selection: SidebarItem?
    @Published var activeTab: DetailTab = .health
    @Published var requestedVolumeToTest: String?
    /// By drive identifier. “Turned on” stays visible until the user dismisses it.
    @Published private(set) var smartNotices: [String: SmartNotice] = [:]
    @Published private(set) var enablingSmart: Set<String> = []
    /// Main window open. When it's closed (menu bar mode), SwiftUI keeps its view hierarchy
    /// alive and keeps updating it, so its content is replaced by an empty view.
    @Published var isMainWindowVisible = true

    /// Lives as long as the app: switching tabs or drives doesn't interrupt a test.
    let benchmark = BenchmarkController()

    private var refreshTimer: Timer?
    private var sampleScheduler: SampleScheduler?
    private var daSession: DASession?
    private var loadTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var identifyCache = IdentifyCache()
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
        // After sleep, a BSD name may belong to another drive: cached Identify data is dropped.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.identifyCache.invalidateAll() }
        }
        loadDisks()
    }

    private func setupHotplug() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        daSession = session

        // Only whole disks matter: volumes, mounted disk images and partitions
        // appearing don't trigger a full discovery.
        let match = [kDADiskDescriptionMediaWholeKey as String: true] as CFDictionary
        // The context is an unretained reference: deinit unregisters the callbacks and unschedules
        // the session, so a released manager (tests create several) is never called back.
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, match, Self.hotplugCallback, context)
        DARegisterDiskDisappearedCallback(session, match, Self.hotplugCallback, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private static let hotplugCallback: DADiskAppearedCallback = { disk, context in
        guard let context else { return }
        let manager = Unmanaged<AppManager>.fromOpaque(context).takeUnretainedValue()
        let bsdName = DADiskGetBSDName(disk).map { String(cString: $0) }
        Task { @MainActor in
            // Appeared or disappeared: whatever is cached under that name may describe another drive.
            if let bsdName { manager.identifyCache.invalidate(bsdName: bsdName) }
            manager.loadDisks()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        loadTask?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let session = daSession {
            let context = Unmanaged.passUnretained(self).toOpaque()
            DAUnregisterCallback(session, unsafeBitCast(Self.hotplugCallback, to: UnsafeMutableRawPointer.self), context)
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    private func startTimer() {
        // Full discovery every 5 min (free space on volumes); health itself
        // is read again every 30 s by SampleScheduler.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadDisks(isAutoRefresh: true) }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func loadDisks(isAutoRefresh: Bool = false) {
        if !isAutoRefresh {
            // Startup and hot-plug only, off the main thread, without waiting for it: a volume that
            // doesn't answer must not freeze the app.
            Task.detached(priority: .utility) { RemovableVolumesProbe.touch() }
        }
        if Self.isDemo {
            disks = DemoData.disks.map {
                RealDisk(physical: $0.physical, snapshot: $0.snapshot, health: $0.health, lastRead: Date())
            }
            volumes = DemoData.volumes
            isLoading = false
            return
        }
        // During a test the drive's queue is saturated: no extra reads are added.
        if isAutoRefresh && benchmark.isRunning { return }

        loadTask?.cancel()
        // Coalesces bursts of DiskArbitration events (plugging in, startup). Read before the task starts:
        // touching a @Published property through a weak self while the manager is being deallocated crashed.
        let delayNs: UInt64 = isLoading ? 50_000_000 : 1_000_000_000
        loadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }

            let knownIdentify = self.identifyCache.known(from: self.disks)
            let (finalDisks, finalVolumes, results) = await Task.detached(priority: .userInitiated) {
                // Filter before any S.M.A.R.T. read: external drives, disk images and
                // virtual disks aren't shown, so there's no point querying them.
                let physicalDisks = DiskDiscovery.listPhysicalDisks().filter(DiskFilter.isMonitored)
                let results = physicalDisks.map { Self.read($0, knownIdentify: knownIdentify[$0.bsdName]) }
                let (disks, volumes) = DiskFilter.filter(disks: results.map(\.disk), volumes: VolumeDiscovery.listVolumes())
                return (disks, volumes, results)
            }.value

            guard !Task.isCancelled else { return }
            if !isAutoRefresh && !self.benchmark.isRunning {
                // Leftover test files: walked in the background, the list is shown without waiting.
                Task.detached(priority: .utility) { BenchCleanup.run(volumes: finalVolumes) }
            }
            self.apply(disks: finalDisks, announceChanges: !self.disks.isEmpty)
            self.updateSmartNotices(results)
            self.volumes = finalVolumes
            self.ensureValidSelection(disks: finalDisks, volumes: finalVolumes)
            self.isLoading = false
        }
    }

    /// Full read of a drive (off the main thread). On ATA, a disabled S.M.A.R.T. is turned on
    /// once per drive if the setting allows it (see `SmartActivator`).
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
                    current = current.withSmartAvailability(.available)
                }
            } catch ATAReadError.smartDisabled {
                current = physical.withCapability(.unsupported(reason: .smartDisabled))
                    .withSmartAvailability(.disabledOnDrive)
            } catch {
                NSLog("Aman Disk: could not read S.M.A.R.T. data for %@ (%@)", physical.bsdName, "\(error)")
                let errorCode: Int32
                if let nvmeErr = error as? NVMeReadError {
                    switch nvmeErr {
                    case .notFound: errorCode = -1
                    case .notNVMe: errorCode = -2
                    case .pluginFailed: errorCode = -3
                    case .readFailed: errorCode = -4
                    case .bufferTooSmall: errorCode = -5
                    case .unknown(let c): errorCode = c
                    }
                } else if let ataErr = error as? ATAReadError {
                    switch ataErr {
                    case .invalidArguments: errorCode = -1
                    case .diskNotFound: errorCode = -2
                    case .mediaNotFound: errorCode = -3
                    case .smartServiceNotFound: errorCode = -4
                    case .pluginCreationFailed: errorCode = -5
                    case .smartDisabled: errorCode = -6
                    case .ioError(let code): errorCode = code
                    case .unknown(let code): errorCode = code
                    case .parseFailed: errorCode = -12
                    }
                } else {
                    errorCode = -99
                }
                current = physical.withCapability(.unsupported(reason: .readFailed(code: "\(errorCode)")))
                    .withSmartAvailability(.error(code: errorCode))
            }
        }
        return (RealDisk(physical: current, snapshot: snapshot, health: health, lastRead: Date()), notice)
    }

    /// Reading obtained and message to show; a successful activation goes into the drive's log.
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

    /// Activation requested by the user (“Turn On S.M.A.R.T.…” or “Try Again”).
    func enableSmart(diskId: String) {
        guard !Self.isDemo, let disk = disk(withId: diskId), !enablingSmart.contains(diskId) else { return }
        enablingSmart.insert(diskId)
        let bsdName = disk.physical.bsdName
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (DiskHealthSnapshot?, SmartNotice?) in
                do {
                    return AppManager.handle(try SmartActivator(memory: AppManager.smartMemory).enable(bsdName: bsdName))
                } catch {
                    // Turned on, but reading it again failed: the next discovery will take care of it.
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

    /// Publishes the new list and reports drives being plugged in and status changes.
    private func apply(disks newDisks: [RealDisk], announceChanges: Bool) {
        if announceChanges {
            let oldById = Dictionary(disks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let newIds = Set(newDisks.map(\.id))
            for disk in newDisks where oldById[disk.id] == nil {
                ToastCenter.shared.show(message: L("\(disk.physical.model) connected", "\(disk.physical.model) connecté"), systemImage: "externaldrive.badge.plus")
            }
            for (id, disk) in oldById where !newIds.contains(id) {
                if benchmark.runningDiskId == id {
                    benchmark.cancelForDisconnection()
                }
                ToastCenter.shared.show(message: L("\(disk.physical.model) disconnected", "\(disk.physical.model) déconnecté"), systemImage: "externaldrive.badge.minus")
                if disk.physical.isExternal {
                    externalDisksHistory[disk.benchmarkKey] = (disk, Date())
                    if selection == .physicalDisk(id) {
                        selection = .disconnectedDisk(disk.benchmarkKey)
                    }
                } else if selection == .physicalDisk(id) {
                    selection = (bootDisk ?? newDisks.first).map { .physicalDisk($0.id) }
                }
            }
            for disk in newDisks {
                if let old = oldById[disk.id], old.snapshot != nil, disk.snapshot != nil, old.health.status != disk.health.status {
                    ToastCenter.shared.show(message: L("\(disk.physical.model): \(disk.health.status.localizedLabel)", "\(disk.physical.model) : \(disk.health.status.localizedLabel)"), systemImage: disk.health.status.symbolName)
                }
            }
        }
        for disk in newDisks where disk.physical.isExternal {
            externalDisksHistory.removeValue(forKey: disk.benchmarkKey)
        }
        let currentlyConnectedKeys = Set(newDisks.map(\.benchmarkKey))
        disconnectedDisks = externalDisksHistory.values
            .filter { !currentlyConnectedKeys.contains($0.disk.benchmarkKey) }
            .map { DisconnectedDisk(disk: $0.disk, lastSeen: $0.lastSeen) }
            .sorted { $0.lastSeen > $1.lastSeen }

        disks = newDisks
        if case .physicalDisk(let id) = selection, !newDisks.contains(where: { $0.id == id }) {
            selection = (bootDisk ?? newDisks.first).map { .physicalDisk($0.id) }
        }
    }

    private func ensureValidSelection(disks: [RealDisk], volumes: [Volume]) {
        switch selection {
        case .physicalDisk(let id):
            if !disks.contains(where: { $0.id == id }) {
                selection = (bootDisk ?? disks.first).map { .physicalDisk($0.id) }
            }
        case .volume(let id):
            if !volumes.contains(where: { $0.id == id }) {
                selection = (bootDisk ?? disks.first).map { .physicalDisk($0.id) }
            }
        case .disconnectedDisk(let key):
            if !disconnectedDisks.contains(where: { $0.id == key }) {
                selection = (bootDisk ?? disks.first).map { .physicalDisk($0.id) }
            }
        case nil:
            break
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

    /// True during a performance test: its sampler takes over the readings.
    var isBenchmarkRunning: Bool { benchmark.isRunning }

    /// Lightweight reading for continuous monitoring: reads the health of all monitored drives already
    /// known again (no new discovery), records a sample and updates the display.
    func sampleNow() async {
        if Self.isDemo { return }
        let targets = disks.filter { $0.physical.healthCapability == .supported && $0.snapshot != nil }
        guard !targets.isEmpty else { return }

        let updated: [RealDisk] = await Task.detached(priority: .utility) {
            // One read at a time: drives are read one after the other.
            // On NVMe, only the 512 bytes of the SMART log are read again (Identify doesn't change).
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

    /// Reading taken by the performance test: keeps the history and the display up to date.
    func recordBenchmarkSnapshot(_ snapshot: DiskHealthSnapshot, date: Date, diskId: String) {
        guard let index = disks.firstIndex(where: { $0.id == diskId }) else { return }
        var newDisks = disks
        newDisks[index] = RealDisk(physical: disks[index].physical, snapshot: snapshot, health: Self.evaluate(snapshot), lastRead: date)
        apply(disks: newDisks, announceChanges: true)
    }

    /// Physical drive that holds the startup volume (“/”), otherwise the first internal drive.
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

    func lastSeenDate(forBsdName bsdName: String) -> Date? {
        disconnectedDisks.first { $0.disk.physical.bsdName == bsdName }?.lastSeen
    }

    func lastSeenDate(forKey key: String) -> Date? {
        disconnectedDisks.first { $0.id == key }?.lastSeen
    }

    func disconnectedDisk(withId id: String) -> DisconnectedDisk? {
        disconnectedDisks.first { $0.id == id }
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
