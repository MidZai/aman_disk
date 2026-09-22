import Foundation
import IOKit
import DiskArbitration

public enum ProtocolDetector {
    public static func detect(bsdName: String) -> (StorageProtocol, MediumType, HealthCapability) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return (.unknown, .unknown, .unsupported(reason: .noSmartInterface))
        }
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == kIOReturnSuccess else {
            return (.unknown, .unknown, .unsupported(reason: .noSmartInterface))
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
        
        guard targetService != 0 else {
            return (.unknown, .unknown, .unsupported(reason: .noSmartInterface))
        }
        
        var isNVMeSmartCapable = false
        var isATASmartCapable = false
        var mediumTypeStr: String? = nil
        
        var current = targetService
        IOObjectRetain(current)
        
        while current != 0 {
            if let capable = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0) as? Bool, capable {
                isNVMeSmartCapable = true
            }
            
            if let capable = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "SMART Capable" as CFString, kCFAllocatorDefault, 0) as? Bool, capable {
                isATASmartCapable = true
            }
            
            if let devChars = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "Device Characteristics" as CFString, kCFAllocatorDefault, 0) as? [String: Any] {
                if mediumTypeStr == nil, let mt = devChars["Medium Type"] as? String {
                    mediumTypeStr = mt
                }
            }
            
            var parent: io_object_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr == kIOReturnSuccess && parent != 0 {
                current = parent
            } else {
                break
            }
        }
        
        var daProtocol = ""
        var daModel = ""
        if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, targetService),
           let desc = DADiskCopyDescription(disk) as? [String: Any] {
            daProtocol = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
            daModel = desc[kDADiskDescriptionDeviceModelKey as String] as? String ?? ""
        }
        
        IOObjectRelease(targetService)
        
        let mediumType: MediumType
        if mediumTypeStr == "Solid State" {
            mediumType = .solidState
        } else if mediumTypeStr == "Rotational" {
            mediumType = .rotational
        } else {
            mediumType = .unknown
        }
        
        if isNVMeSmartCapable {
            return (.nvme, mediumType, .supported)
        }
        if isATASmartCapable {
            return (.ata, mediumType, .supported)
        }
        if daProtocol == "USB" || daProtocol == "USB-C" || daProtocol == "USB (Attached SCSI)" {
            return (.usb, mediumType, .unsupported(reason: .usbBridge))
        }
        if daProtocol == "Secure Digital" || daProtocol == "SD" || daModel.contains("SD Card Reader") {
            return (.sdCard, mediumType, .unsupported(reason: .sdCardReader))
        }
        if daProtocol == "Virtual Interface" || daProtocol == "Disk Image" || daModel.contains("VMware") || daModel.contains("VBOX") || daModel.contains("Parallels") || daModel.contains("Virtual") {
            return (.virtualDisk, mediumType, .unsupported(reason: .virtualDisk))
        }
        
        return (.unknown, mediumType, .unsupported(reason: .noSmartInterface))
    }
}
