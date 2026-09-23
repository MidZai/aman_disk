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
    @Published var disks: [RealDisk] = []
    @Published var volumes: [Volume] = []
    @Published var needsSudo: Bool = false
    @Published var ignoreSudo: Bool = false
    @Published var isLoading: Bool = true
    @Published var showDetails: Bool = false
    @Published var showRawValues: Bool = false
    @Published var selection: SidebarItem? = nil

    private var refreshTimer: Timer?
    private var daSession: DASession?
    // P3: Retained opaque pointer used in DiskArbitration callbacks.
    // Balanced by the release in deinit.
    private var daContext: UnsafeMutableRawPointer?
    
    public init() {
        startTimer()
        setupHotplug()
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

    
    func loadDisks(isAutoRefresh: Bool = false) {
        if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1" {
            self.disks = DemoData.disks.map { 
                RealDisk(physical: $0.physical, snapshot: $0.snapshot, health: $0.health, lastRead: Date()) 
            }
            self.volumes = DemoData.volumes
            self.isLoading = false
            return
        }
        
        if !isAutoRefresh { self.isLoading = true }
        
        // B7: Use Task (inherits @MainActor context) + detached background work,
        // then await back on MainActor — no DispatchQueue.main.async needed.
        Task { [weak self] in
            guard let self else { return }
            
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
                            }
                            
                            if let snap = snapshot {
                                switch snap {
                                case .nvme(let smartLog, let identify):
                                    health = HealthEngine.evaluate(smart: smartLog, identify: identify)
                                    let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
                                    let sample = HistorySample(
                                        date: Date(),
                                        temperatureC: smartLog.temperatureCelsius,
                                        percentageUsed: Int(smartLog.percentageUsed),
                                        dataUnitsWritten: smartLog.dataUnitsWritten,
                                        dataUnitsRead: smartLog.dataUnitsRead,
                                        powerOnHours: smartLog.powerOnHours,
                                        mediaErrors: smartLog.mediaErrors,
                                        availableSpare: Int(smartLog.availableSpare)
                                    )
                                    HistoryStore.shared.append(sample, for: key)
                                    
                                case .ata(let ataSnapshot):
                                    health = ATAHealthEvaluator.evaluate(snapshot: ataSnapshot)
                                    let profile = ATACatalog.profile(for: ataSnapshot.model)
                                    
                                    var temp: Int? = nil
                                    // B6: Store raw byte counts. The /512000 divisor was arbitrary
                                    // and incompatible with the display in StatTile. Formatters handle
                                    // human-readable conversion at display time.
                                    var written: UInt64? = nil
                                    var read: UInt64? = nil
                                    var hours: UInt64? = nil
                                    var used: Int? = nil
                                    var errors: UInt64? = nil
                                    let spare: Int? = nil   // ATA does not expose available-spare

                                    
                                    for attr in ataSnapshot.attributes {
                                        let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                                        switch info.role {
                                        case .temperature:
                                            temp = attr.value(for: .temperature).map { Int($0) }
                                        case .hostWritesBytes(let mult):
                                            // B6: Store value in bytes (rawValue × multiplier).
                                            written = attr.rawValue * mult
                                        case .hostReadsBytes(let mult):
                                            // B6: Store value in bytes (rawValue × multiplier).
                                            read = attr.rawValue * mult
                                        case .powerOnHours:
                                            hours = attr.value(for: .powerOnHours)
                                        case .lifeRemainingPercentNormalized:
                                            used = 100 - Int(attr.current)
                                        case .reallocated, .pending, .uncorrectable:
                                            errors = (errors ?? 0) + attr.rawValue
                                        default:
                                            break
                                        }
                                    }
                                    
                                    let key = DiskIdentity.key(model: ataSnapshot.model, serial: ataSnapshot.serialNumber)
                                    let sample = HistorySample(
                                        date: Date(),
                                        temperatureC: temp,
                                        percentageUsed: used,
                                        dataUnitsWritten: written,
                                        dataUnitsRead: read,
                                        powerOnHours: hours,
                                        mediaErrors: errors,
                                        availableSpare: spare
                                    )
                                    HistoryStore.shared.append(sample, for: key)
                                }
                            }
                        } catch let error as ATAReadError where error == .smartDisabled {
                            currentPhysical = currentPhysical.withCapability(.unsupported(reason: .smartDisabled))
                        } catch {
                            currentPhysical = currentPhysical.withCapability(.unsupported(reason: .readFailed(code: "\(error)")))
                        }
                    }
                    
                    newDisks.append(RealDisk(physical: currentPhysical, snapshot: snapshot, health: health, lastRead: Date()))
                }
                
                let volumes = VolumeDiscovery.listVolumes()
                return (newDisks, volumes)
            }.value
            
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

    
    func isFusionDriveMember(_ disk: RealDisk) -> Bool {
        volumes.contains { $0.physicalDiskBSDNames.count >= 2 && $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
    }
}
