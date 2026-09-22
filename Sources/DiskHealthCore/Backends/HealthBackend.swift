import Foundation

public enum StorageProtocol: String, Codable, Hashable {
    case nvme, ata, sdCard, virtualDisk, usb, unknown
}

public enum MediumType: String, Codable, Hashable {
    case solidState, rotational, unknown
}

public enum HealthCapability: Codable, Equatable, Hashable {
    case supported
    case unsupported(reason: UnsupportedReason)
}

public enum UnsupportedReason: String, Codable, Hashable {
    case usbBridge
    case sdCardReader
    case virtualDisk
    case smartDisabled
    case noSmartInterface
    case readFailed
}

public protocol HealthBackend {
    static func canHandle(bsdName: String) -> Bool
    static func read(bsdName: String) throws -> DiskHealthSnapshot
}
