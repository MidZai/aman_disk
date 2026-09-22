import Foundation

public enum StorageProtocol: String, Codable, Hashable {
    case nvme, ata, pcieAhci, sdCard, virtualDisk, usb, unknown
}

public enum MediumType: String, Codable, Hashable {
    case solidState, rotational, unknown
}

public enum HealthCapability: Codable, Equatable, Hashable {
    case supported
    case unsupported(reason: UnsupportedReason)
}

public enum UnsupportedReason: Codable, Equatable, Hashable {
    case usbBridge
    case sdCardReader
    case virtualDisk
    case smartDisabled
    case noSmartInterface
    case readFailed(code: String)
    
    public var rawValue: String {
        switch self {
        case .usbBridge: return "usbBridge"
        case .sdCardReader: return "sdCardReader"
        case .virtualDisk: return "virtualDisk"
        case .smartDisabled: return "smartDisabled"
        case .noSmartInterface: return "noSmartInterface"
        case .readFailed(let code): return "readFailed(\(code))"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, code
    }
    
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
            switch str {
            case "usbBridge": self = .usbBridge
            case "sdCardReader": self = .sdCardReader
            case "virtualDisk": self = .virtualDisk
            case "smartDisabled": self = .smartDisabled
            case "noSmartInterface": self = .noSmartInterface
            default:
                if str.hasPrefix("readFailed(") && str.hasSuffix(")") {
                    let start = str.index(str.startIndex, offsetBy: 11)
                    let end = str.index(str.endIndex, offsetBy: -1)
                    self = .readFailed(code: String(str[start..<end]))
                } else if str == "readFailed" {
                    self = .readFailed(code: "unknown")
                } else {
                    self = .readFailed(code: str)
                }
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "usbBridge": self = .usbBridge
        case "sdCardReader": self = .sdCardReader
        case "virtualDisk": self = .virtualDisk
        case "smartDisabled": self = .smartDisabled
        case "noSmartInterface": self = .noSmartInterface
        case "readFailed":
            let code = try container.decodeIfPresent(String.self, forKey: .code) ?? "unknown"
            self = .readFailed(code: code)
        default:
            self = .noSmartInterface
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .usbBridge, .sdCardReader, .virtualDisk, .smartDisabled, .noSmartInterface:
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        case .readFailed(let code):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("readFailed", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }
}

public protocol HealthBackend {
    static func canHandle(bsdName: String) -> Bool
    static func read(bsdName: String) throws -> DiskHealthSnapshot
}
