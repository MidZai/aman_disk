import Foundation
import IOKit

public enum IOKitDiagnostics {
    /// Keys whose value identifies the device or the user.
    static func isSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.contains("serial") || k.contains("uuid") || k.contains("guid") || k.contains("wwn")
            || k.contains("mac address") || k.contains("macaddress")
    }

    /// Readable, masked value. Recursive: IOKit stores the serial number in nested
    /// dictionaries (“Device Characteristics” › “Serial Number”), which used to be copied as is.
    public static func maskValue(key: String, value: Any) -> String {
        if isSensitive(key) {
            return "<masked>"
        }
        if let dict = value as? [String: Any] {
            let inner = dict.keys.sorted().map { "\($0)=\(maskValue(key: $0, value: dict[$0]!))" }
            return "{" + inner.joined(separator: ", ") + "}"
        }
        if let array = value as? [Any] {
            return "(" + array.map { maskValue(key: key, value: $0) }.joined(separator: ", ") + ")"
        }
        if let s = value as? String {
            // UUID format (8-4-4-4-12 hexadecimal).
            if s.count == 36 && s.filter({ $0 == "-" }).count == 4 {
                return "<masked>"
            }
            return s
        }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
        }
        if let n = value as? NSNumber {
            return n.stringValue
        }
        if let d = value as? Data {
            return "<data \(d.count) bytes>"
        }
        return "\(value)"
    }

    public static func sanitizeProperties(_ dict: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (k, v) in dict {
            result[k] = maskValue(key: k, value: v)
        }
        return result
    }
    
    public static func collectParentChain(bsdName: String) -> [IOKitNodeDiagnostic] {
        let targetService = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
        guard targetService != 0 else { return [] }
        
        var chain: [IOKitNodeDiagnostic] = []
        var current = targetService
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &classNameBuf)
            let className = String(cString: classNameBuf)
            
            var propsDict: [String: String] = [:]
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = properties?.takeRetainedValue() as? [String: Any] {
                propsDict = sanitizeProperties(dict)
            }
            
            chain.append(IOKitNodeDiagnostic(className: className, properties: propsDict))
            
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }
        
        return chain
    }
}
