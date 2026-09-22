import Foundation

public struct ATASmartAttribute: Codable, Equatable, Hashable, Identifiable {
    public let id: UInt8
    public let flags: UInt16
    public let current: UInt8
    public let worst: UInt8
    public let threshold: UInt8
    public let raw: [UInt8]
    public let rawValue: UInt64
    
    public init(id: UInt8, flags: UInt16, current: UInt8, worst: UInt8, threshold: UInt8, raw: [UInt8], rawValue: UInt64) {
        self.id = id
        self.flags = flags
        self.current = current
        self.worst = worst
        self.threshold = threshold
        self.raw = raw
        self.rawValue = rawValue
    }
}

public struct ATASmartSnapshot: Codable, Equatable, Hashable {
    public let attributes: [ATASmartAttribute]
    public let model: String
    public let firmware: String
    public let serialNumber: String
    public let rotationRate: Int
    public let thresholdExceeded: Bool
    public let checksumValid: Bool
    
    public init(attributes: [ATASmartAttribute], model: String, firmware: String, serialNumber: String, rotationRate: Int, thresholdExceeded: Bool, checksumValid: Bool) {
        self.attributes = attributes
        self.model = model
        self.firmware = firmware
        self.serialNumber = serialNumber
        self.rotationRate = rotationRate
        self.thresholdExceeded = thresholdExceeded
        self.checksumValid = checksumValid
    }
}

public enum DiskHealthSnapshot: Codable, Equatable, Hashable {
    case nvme(NVMeSmartLog, NVMeIdentify)
    case ata(ATASmartSnapshot)
    
    enum CodingKeys: String, CodingKey {
        case protocolType = "protocol"
        case smart, identify
        // For ATA, we embed everything from ATASmartSnapshot
        case attributes, model, firmware, serialNumber, rotationRate, thresholdExceeded, checksumValid
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .protocolType) ?? "nvme" // default if old
        
        if type == "nvme" || container.contains(.smart) {
            let smart = try container.decode(NVMeSmartLog.self, forKey: .smart)
            let id = try container.decode(NVMeIdentify.self, forKey: .identify)
            self = .nvme(smart, id)
        } else if type == "ata" {
            let attrs = try container.decode([ATASmartAttribute].self, forKey: .attributes)
            let model = try container.decode(String.self, forKey: .model)
            let fw = try container.decode(String.self, forKey: .firmware)
            let sn = try container.decode(String.self, forKey: .serialNumber)
            let rot = try container.decode(Int.self, forKey: .rotationRate)
            let thresh = try container.decode(Bool.self, forKey: .thresholdExceeded)
            let check = try container.decode(Bool.self, forKey: .checksumValid)
            self = .ata(ATASmartSnapshot(attributes: attrs, model: model, firmware: fw, serialNumber: sn, rotationRate: rot, thresholdExceeded: thresh, checksumValid: check))
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown protocol"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .nvme(let smart, let id):
            try container.encode("nvme", forKey: .protocolType)
            try container.encode(smart, forKey: .smart)
            try container.encode(id, forKey: .identify)
        case .ata(let a):
            try container.encode("ata", forKey: .protocolType)
            try container.encode(a.attributes, forKey: .attributes)
            try container.encode(a.model, forKey: .model)
            try container.encode(a.firmware, forKey: .firmware)
            try container.encode(a.serialNumber, forKey: .serialNumber)
            try container.encode(a.rotationRate, forKey: .rotationRate)
            try container.encode(a.thresholdExceeded, forKey: .thresholdExceeded)
            try container.encode(a.checksumValid, forKey: .checksumValid)
        }
    }
}

