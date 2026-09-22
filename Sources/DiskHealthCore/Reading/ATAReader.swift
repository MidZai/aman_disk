import Foundation
import CDiskIO

public enum ATAReadError: Error, Equatable {
    case invalidArguments
    case diskNotFound
    case mediaNotFound
    case smartServiceNotFound
    case pluginCreationFailed
    case smartDisabled
    case unknown(Int32)
}

public enum ATAReader {
    private static func mapError(_ code: Int32) -> ATAReadError {
        switch code {
        case -1: return .invalidArguments
        case -2: return .diskNotFound
        case -3: return .mediaNotFound
        case -4: return .smartServiceNotFound
        case -5: return .pluginCreationFailed
        case -6: return .smartDisabled
        default: return .unknown(code)
        }
    }
    
    public static func readSmartData(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_data(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readSmartThresholds(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_thresholds(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readIdentify(bsdName: String) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 512)
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_identify(cString, &buffer, Int32(buffer.count))
        }
        
        if result == 0 {
            return Data(buffer)
        } else {
            throw mapError(result)
        }
    }
    
    public static func readSmartStatus(bsdName: String) throws -> Bool {
        var exceeded: Int32 = 0
        let result = bsdName.withCString { cString in
            cdiskio_read_ata_smart_status(cString, &exceeded)
        }
        
        if result == 0 {
            return exceeded != 0
        } else {
            throw mapError(result)
        }
    }
}
