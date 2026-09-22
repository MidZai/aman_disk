import Foundation
import DiskHealthCore

enum SidebarItem: Hashable {
    case physicalDisk(String)
    case volume(String)
}

public struct RealDisk: Identifiable, Equatable, Codable {
    public var id: String { physical.bsdName }
    public let physical: PhysicalDisk
    public let smart: NVMeSmartLog?
    public let identify: NVMeIdentify?
    public let health: HealthAssessment
    public let lastRead: Date
    
    public init(physical: PhysicalDisk, smart: NVMeSmartLog?, identify: NVMeIdentify?, health: HealthAssessment, lastRead: Date = Date()) {
        self.physical = physical
        self.smart = smart
        self.identify = identify
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
    
    public init() {
        startTimer()
        setupHotplug()
        Task { @MainActor in loadDisks() }
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
        
        let context = Unmanaged.passUnretained(self).toOpaque()
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
                RealDisk(physical: $0.physical, smart: $0.smart, identify: $0.identify, health: $0.health, lastRead: Date()) 
            }
            self.volumes = []
            self.isLoading = false
            return
        }
        
        if !isAutoRefresh { isLoading = true }
        // On background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let physicalDisks = DiskDiscovery.listPhysicalDisks()
            var newDisks: [RealDisk] = []
            var privilegesMissing = false
            
            for physical in physicalDisks {
                if physical.connection == .nvmeInternal || physical.connection == .nvmeExternal {
                    do {
                        let smartData = try NVMeReader.readSmartLog(bsdName: physical.bsdName)
                        let identifyData = try NVMeReader.readIdentify(bsdName: physical.bsdName)
                        
                        if let smartLog = NVMeSmartParser.parse(smartData),
                           let identify = NVMeIdentifyParser.parse(identifyData) {
                            let health = HealthEngine.evaluate(smart: smartLog, identify: identify)
                            newDisks.append(RealDisk(physical: physical, smart: smartLog, identify: identify, health: health, lastRead: Date()))
                            
                            // Save to history
                            let key = DiskIdentity.key(model: identify.modelNumber, serial: identify.serialNumber)
                            let sample = HistorySample(
                                date: Date(),
                                temperatureC: smartLog.temperatureCelsius,
                                percentageUsed: smartLog.percentageUsed,
                                dataUnitsWritten: smartLog.dataUnitsWritten,
                                dataUnitsRead: smartLog.dataUnitsRead,
                                powerOnHours: smartLog.powerOnHours,
                                mediaErrors: smartLog.mediaErrors,
                                availableSpare: smartLog.availableSpare
                            )
                            HistoryStore.shared.append(sample, for: key)
                        } else {
                            let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Données SMART illisibles"])
                            newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health, lastRead: Date()))
                        }
                    } catch {
                        privilegesMissing = true
                        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Erreur de lecture: \(error.localizedDescription)"])
                        newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health, lastRead: Date()))
                    }
                } else {
                    let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Santé non lisible"])
                    newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health, lastRead: Date()))
                }
            }
            

            let volumes = VolumeDiscovery.listVolumes()
            DispatchQueue.main.async {
                // Hotplug detection for toasts
                if !self.disks.isEmpty {
                    let oldIds = Set(self.disks.map { $0.id })
                    let newIds = Set(newDisks.map { $0.id })
                    
                    let added = newIds.subtracting(oldIds)
                    let removed = oldIds.subtracting(newIds)
                    
                    for id in added {
                        if let disk = newDisks.first(where: { $0.id == id }) {
                            ToastCenter.shared.show(message: "\(disk.physical.model) connecté", systemImage: "externaldrive.badge.plus")
                        }
                    }
                    for id in removed {
                        if let disk = self.disks.first(where: { $0.id == id }) {
                            ToastCenter.shared.show(message: "\(disk.physical.model) déconnecté", systemImage: "externaldrive.badge.minus")
                            
                            if case .physicalDisk(let selId) = self.selection, selId == id {
                                if let internalDisk = newDisks.first(where: { $0.physical.isInternal }) {
                                    self.selection = .physicalDisk(internalDisk.id)
                                } else {
                                    self.selection = nil
                                }
                            }
                        }
                    }
                    
                    // Health change detection
                    if isAutoRefresh {
                        for newDisk in newDisks {
                            if let oldDisk = self.disks.first(where: { $0.id == newDisk.id }) {
                                if oldDisk.health.status != newDisk.health.status {
                                    let statusStr = newDisk.health.status == .good ? "En bonne santé" : (newDisk.health.status == .caution ? "À surveiller" : "Défaillance probable")
                                    ToastCenter.shared.show(message: "L'état de \(newDisk.physical.model) est passé à : \(statusStr)", systemImage: "exclamationmark.triangle")
                                }
                            }
                        }
                    }
                }
                
                self.disks = newDisks
                self.volumes = volumes

                self.needsSudo = privilegesMissing
                if !isAutoRefresh { self.isLoading = false }
            }
        }
    }
}
