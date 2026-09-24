import Foundation
import IOKit

public enum IOKitDiagnostics {
    /// Clés dont la valeur identifie l'appareil ou l'utilisateur.
    static func isSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.contains("serial") || k.contains("uuid") || k.contains("guid") || k.contains("wwn")
            || k.contains("mac address") || k.contains("macaddress")
    }

    /// Valeur lisible et masquée. Récursive : IOKit range le numéro de série dans des dictionnaires
    /// imbriqués (« Device Characteristics » › « Serial Number »), qui étaient recopiés tels quels.
    public static func maskValue(key: String, value: Any) -> String {
        if isSensitive(key) {
            return "<masqué>"
        }
        if let dict = value as? [String: Any] {
            let inner = dict.keys.sorted().map { "\($0)=\(maskValue(key: $0, value: dict[$0]!))" }
            return "{" + inner.joined(separator: ", ") + "}"
        }
        if let array = value as? [Any] {
            return "(" + array.map { maskValue(key: key, value: $0) }.joined(separator: ", ") + ")"
        }
        if let s = value as? String {
            // Format UUID (8-4-4-4-12 hexadécimal).
            if s.count == 36 && s.filter({ $0 == "-" }).count == 4 {
                return "<masqué>"
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
