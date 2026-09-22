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
    
    public init() {
        startTimer()
    }
    
    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadDisks(isAutoRefresh: true) }
        }
    }
    
    func loadDisks(isAutoRefresh: Bool = false) {
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
                            if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] != "1" {
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
                            }
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
                self.disks = newDisks
                self.volumes = volumes

                self.needsSudo = privilegesMissing
                if !isAutoRefresh { self.isLoading = false }
            }
        }
    }
}
