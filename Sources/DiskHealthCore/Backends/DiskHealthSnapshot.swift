import Foundation

public struct ATASmartAttribute: Codable, Equatable, Hashable {
    public let id: UInt8
    public let flags: UInt16
    public let current: UInt8
    public let worst: UInt8
    public let threshold: UInt8
    public let raw: [UInt8]
    public let rawValue: UInt64
}

public struct ATASmartSnapshot: Codable, Equatable, Hashable {
    public let attributes: [ATASmartAttribute]
    public let model: String
    public let firmware: String
    public let serialNumber: String
    public let rotationRate: Int
    public let thresholdExceeded: Bool
    public let checksumValid: Bool
}

public enum DiskHealthSnapshot: Codable {
    case nvme(NVMeSmartLog, NVMeIdentify)
    case ata(ATASmartSnapshot)
}
