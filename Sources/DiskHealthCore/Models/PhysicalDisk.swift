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
    public let usbVendorID: UInt16?     // only if connection == .usb
    public let usbProductID: UInt16?
    public let protocolType: StorageProtocol
    public let mediumType: MediumType
    public let healthCapability: HealthCapability
    public let isVirtual: Bool
    public let isDiskImage: Bool

    public init(bsdName: String, model: String, sizeBytes: UInt64, isInternal: Bool, connection: Connection, volumeNames: [String], usbVendorID: UInt16? = nil, usbProductID: UInt16? = nil, protocolType: StorageProtocol, mediumType: MediumType, healthCapability: HealthCapability, isVirtual: Bool = false, isDiskImage: Bool = false) {
        self.bsdName = bsdName
        self.model = model
        self.sizeBytes = sizeBytes
        self.isInternal = isInternal
        self.connection = connection
        self.volumeNames = volumeNames
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.protocolType = protocolType
        self.mediumType = mediumType
        self.healthCapability = healthCapability
        self.isVirtual = isVirtual
        self.isDiskImage = isDiskImage
    }

    // Custom Decodable so old JSON without isVirtual/isDiskImage can still be decoded.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bsdName         = try c.decode(String.self, forKey: .bsdName)
        model           = try c.decode(String.self, forKey: .model)
        sizeBytes       = try c.decode(UInt64.self, forKey: .sizeBytes)
        isInternal      = try c.decode(Bool.self, forKey: .isInternal)
        connection      = try c.decode(Connection.self, forKey: .connection)
        volumeNames     = try c.decode([String].self, forKey: .volumeNames)
        usbVendorID     = try c.decodeIfPresent(UInt16.self, forKey: .usbVendorID)
        usbProductID    = try c.decodeIfPresent(UInt16.self, forKey: .usbProductID)
        protocolType    = try c.decode(StorageProtocol.self, forKey: .protocolType)
        mediumType      = try c.decode(MediumType.self, forKey: .mediumType)
        healthCapability = try c.decode(HealthCapability.self, forKey: .healthCapability)
        isVirtual       = try c.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        isDiskImage     = try c.decodeIfPresent(Bool.self, forKey: .isDiskImage) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case bsdName, model, sizeBytes, isInternal, connection, volumeNames
        case usbVendorID, usbProductID, protocolType, mediumType, healthCapability
        case isVirtual, isDiskImage
    }
    
    public func withCapability(_ capability: HealthCapability) -> PhysicalDisk {
        PhysicalDisk(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: connection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: capability,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }
}
