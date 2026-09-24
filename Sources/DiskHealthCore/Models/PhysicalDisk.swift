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
    public var isExternal: Bool { !isInternal }
    public let connection: Connection
    public let driveConnection: DriveConnection
    public let volumeNames: [String]
    public let usbVendorID: UInt16?     // only if connection == .usb
    public let usbProductID: UInt16?
    public let protocolType: StorageProtocol
    public let mediumType: MediumType
    public let healthCapability: HealthCapability
    public let smartAvailability: SmartAvailability?
    public let isVirtual: Bool
    public let isDiskImage: Bool

    public init(
        bsdName: String,
        model: String,
        sizeBytes: UInt64,
        isInternal: Bool,
        connection: Connection,
        driveConnection: DriveConnection? = nil,
        volumeNames: [String],
        usbVendorID: UInt16? = nil,
        usbProductID: UInt16? = nil,
        protocolType: StorageProtocol,
        mediumType: MediumType,
        healthCapability: HealthCapability,
        smartAvailability: SmartAvailability? = nil,
        isVirtual: Bool = false,
        isDiskImage: Bool = false
    ) {
        self.bsdName = bsdName
        self.model = model
        self.sizeBytes = sizeBytes
        self.isInternal = isInternal
        self.connection = connection
        if let dc = driveConnection {
            self.driveConnection = dc
        } else {
            switch connection {
            case .nvmeInternal: self.driveConnection = .internalNVMe
            case .nvmeExternal: self.driveConnection = .thunderboltNVMe
            case .usb:          self.driveConnection = .usb
            case .sata:         self.driveConnection = isInternal ? .internalSATA : .other("SATA")
            case .other:
                if protocolType == .pcieAhci && isInternal {
                    self.driveConnection = .internalAHCI
                } else {
                    self.driveConnection = .other(isInternal ? "Internal" : "Other")
                }
            }
        }
        self.volumeNames = volumeNames
        self.usbVendorID = usbVendorID
        self.usbProductID = usbProductID
        self.protocolType = protocolType
        self.mediumType = mediumType
        self.healthCapability = healthCapability
        self.smartAvailability = smartAvailability
        self.isVirtual = isVirtual
        self.isDiskImage = isDiskImage
    }

    /// Convenience initializer when initialized with `driveConnection`.
    public init(
        bsdName: String,
        model: String,
        sizeBytes: UInt64,
        isInternal: Bool,
        driveConnection: DriveConnection,
        volumeNames: [String],
        usbVendorID: UInt16? = nil,
        usbProductID: UInt16? = nil,
        protocolType: StorageProtocol,
        mediumType: MediumType,
        healthCapability: HealthCapability,
        smartAvailability: SmartAvailability? = nil,
        isVirtual: Bool = false,
        isDiskImage: Bool = false
    ) {
        let conn: Connection
        switch driveConnection {
        case .internalNVMe: conn = .nvmeInternal
        case .internalAHCI: conn = .other
        case .internalSATA: conn = .sata
        case .thunderboltNVMe: conn = .nvmeExternal
        case .usb: conn = .usb
        case .other: conn = .other
        }
        self.init(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: conn,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: healthCapability,
            smartAvailability: smartAvailability,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }

    // Custom Decodable so older JSON without isVirtual/isDiskImage/driveConnection can still be decoded.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bsdName         = try c.decode(String.self, forKey: .bsdName)
        model           = try c.decode(String.self, forKey: .model)
        sizeBytes       = try c.decode(UInt64.self, forKey: .sizeBytes)
        isInternal      = try c.decode(Bool.self, forKey: .isInternal)
        let decodedConn = try c.decode(Connection.self, forKey: .connection)
        connection      = decodedConn
        volumeNames     = try c.decode([String].self, forKey: .volumeNames)
        usbVendorID     = try c.decodeIfPresent(UInt16.self, forKey: .usbVendorID)
        usbProductID    = try c.decodeIfPresent(UInt16.self, forKey: .usbProductID)
        protocolType    = try c.decode(StorageProtocol.self, forKey: .protocolType)
        mediumType      = try c.decode(MediumType.self, forKey: .mediumType)
        healthCapability = try c.decode(HealthCapability.self, forKey: .healthCapability)
        smartAvailability = try c.decodeIfPresent(SmartAvailability.self, forKey: .smartAvailability)
        isVirtual       = try c.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        isDiskImage     = try c.decodeIfPresent(Bool.self, forKey: .isDiskImage) ?? false

        if let dc = try c.decodeIfPresent(DriveConnection.self, forKey: .driveConnection) {
            driveConnection = dc
        } else {
            switch decodedConn {
            case .nvmeInternal: driveConnection = .internalNVMe
            case .nvmeExternal: driveConnection = .thunderboltNVMe
            case .usb:          driveConnection = .usb
            case .sata:         driveConnection = isInternal ? .internalSATA : .other("SATA")
            case .other:
                if protocolType == .pcieAhci && isInternal {
                    driveConnection = .internalAHCI
                } else {
                    driveConnection = .other(isInternal ? "Internal" : "Other")
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bsdName, model, sizeBytes, isInternal, connection, driveConnection, volumeNames
        case usbVendorID, usbProductID, protocolType, mediumType, healthCapability, smartAvailability
        case isVirtual, isDiskImage
    }

    public func withCapability(_ capability: HealthCapability) -> PhysicalDisk {
        PhysicalDisk(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: connection,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: capability,
            smartAvailability: smartAvailability,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }

    public func withSmartAvailability(_ availability: SmartAvailability) -> PhysicalDisk {
        PhysicalDisk(
            bsdName: bsdName,
            model: model,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            connection: connection,
            driveConnection: driveConnection,
            volumeNames: volumeNames,
            usbVendorID: usbVendorID,
            usbProductID: usbProductID,
            protocolType: protocolType,
            mediumType: mediumType,
            healthCapability: healthCapability,
            smartAvailability: availability,
            isVirtual: isVirtual,
            isDiskImage: isDiskImage
        )
    }
}
