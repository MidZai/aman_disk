import Foundation

public struct NVMeIdentify: Codable, Equatable {
    public let serialNumber: String
    public let modelNumber: String
    public let firmwareRevision: String
    public let warningTempKelvin: UInt16
    public let criticalTempKelvin: UInt16
    public let totalCapacityBytes: UInt64
}
