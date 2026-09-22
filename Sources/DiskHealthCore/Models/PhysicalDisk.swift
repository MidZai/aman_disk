import Foundation

public enum Connection: String, Codable {
    case nvmeInternal, nvmeExternal, usb, sata, other
}

public struct PhysicalDisk: Codable, Identifiable, Hashable {
    public var id: String { bsdName }
    public let bsdName: String
    public let model: String
    public let sizeBytes: UInt64
    public let isInternal: Bool
    public let connection: Connection
    public let volumeNames: [String]
    public let usbVendorID: UInt16?     // uniquement si connection == .usb
    public let usbProductID: UInt16?

    public init(bsdName: String, model: String, sizeBytes: UInt64, isInternal: Bool, connection: Connection, volumeNames: [String], usbVendorID: UInt16? = nil, usbProductID: UInt16? = nil) {
        self.bsdName = bsdName
        self.model = model
        self.sizeBytes = sizeBytes
        self.isInternal = isInternal
        self.connection = connection
        self.volumeNames = volumeNames
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
    }
}
