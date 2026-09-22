import Foundation
import IOKit

public enum IOKitDiagnostics {
    public static func maskValue(key: String, value: Any) -> String {
        let lowerKey = key.lowercased()
        if lowerKey.contains("serial") || lowerKey.contains("uuid") || lowerKey.contains("guid") {
            return "<masqué>"
        }
        if let s = value as? String {
            // Check for UUID-like format (8-4-4-4-12 hex)
            if s.count == 36 && s.filter({ $0 == "-" }).count == 4 {
                return "<masqué>"
            }
            return s
        }
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
            let b = CFBooleanGetValue((value as! CFBoolean))
            return b ? "true" : "false"
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
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == kIOReturnSuccess else {
            return []
        }
        
        var targetService: io_object_t = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault, 0) as? String, name == bsdName {
                targetService = service
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        
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
