import Foundation
import DiskHealthCore

public protocol TemperatureSamplerDelegate: AnyObject {
    func temperatureSamplerDidUpdate(_ temp: Int)
}

public class TemperatureSampler {
    private let bsdName: String
    private let protocolType: StorageProtocol
    private let connection: Connection
    private var timer: Timer?
    private let queue: DispatchQueue
    public weak var delegate: TemperatureSamplerDelegate?
    
    public private(set) var currentTempC: Int?
    public private(set) var maxTempC: Int?
    
    public init(bsdName: String, protocolType: StorageProtocol, connection: Connection) {
        self.bsdName = bsdName
        self.protocolType = protocolType
        self.connection = connection
        self.queue = DispatchQueue(label: "io.github.aman-disk.TemperatureSampler", qos: .background)
    }
    
    public func start() {
        let interval: TimeInterval = connection == .nvmeInternal || connection == .nvmeExternal ? 2.0 : 5.0
        
        queue.async {
            self.sample()
            
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.queue.async {
                    self?.sample()
                }
            }
            RunLoop.current.add(t, forMode: .common)
            self.timer = t
            RunLoop.current.run()
        }
    }
    
    public func stop() {
        queue.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    private func sample() {
        var temp: Int? = nil
        if protocolType == .nvme {
            if let snapshot = try? NVMeBackend.read(bsdName: bsdName) {
                if case .nvme(let smartLog, _) = snapshot {
                    temp = smartLog.temperatureCelsius
                }
            }
        } else if protocolType == .ata || protocolType == .pcieAhci {
            if let snapshot = try? ATABackend.read(bsdName: bsdName) {
                if case .ata(let ata) = snapshot {
                    let profile = ATACatalog.profile(for: ata.model)
                    for attr in ata.attributes {
                        let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                        if info.role == .temperature {
                            if let v = attr.value(for: .temperature) {
                                temp = Int(v)
                            }
                            break
                        }
                    }
                }
            }
        }
        
        if let t = temp {
            currentTempC = t
            if let mt = maxTempC {
                maxTempC = max(mt, t)
            } else {
                maxTempC = t
            }
            delegate?.temperatureSamplerDidUpdate(t)
        }
    }
}
