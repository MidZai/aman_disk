import Foundation
import DiskHealthCore

public struct RealDisk: Identifiable, Equatable {
    public var id: String { physical.bsdName }
    public let physical: PhysicalDisk
    public let smart: NVMeSmartLog?
    public let identify: NVMeIdentify?
    public let health: HealthAssessment
    
    public static func ==(lhs: RealDisk, rhs: RealDisk) -> Bool {
        return lhs.physical == rhs.physical
    }
}

@MainActor
class AppManager: ObservableObject {
    @Published var disks: [RealDisk] = []
    @Published var needsSudo: Bool = false
    @Published var ignoreSudo: Bool = false
    @Published var isLoading: Bool = true
    
    func loadDisks() {
        isLoading = true
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
                            newDisks.append(RealDisk(physical: physical, smart: smartLog, identify: identify, health: health))
                        } else {
                            let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Données SMART illisibles"])
                            newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health))
                        }
                    } catch {
                        privilegesMissing = true
                        let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Erreur de lecture: \(error.localizedDescription)"])
                        newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health))
                    }
                } else {
                    let health = HealthAssessment(status: .unknown, healthPercent: nil, reasons: ["Santé non lisible"])
                    newDisks.append(RealDisk(physical: physical, smart: nil, identify: nil, health: health))
                }
            }
            
            DispatchQueue.main.async {
                self.disks = newDisks
                self.needsSudo = privilegesMissing
                self.isLoading = false
            }
        }
    }
}
