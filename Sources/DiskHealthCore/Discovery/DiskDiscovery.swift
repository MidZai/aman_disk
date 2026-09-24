import Foundation
import IOKit
import DiskArbitration

public enum DiskDiscovery {
    public static func listPhysicalDisks() -> [PhysicalDisk] {
        var disks: [PhysicalDisk] = []
        
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return []
        }
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == kIOReturnSuccess else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        
        var diskService: io_object_t = IOIteratorNext(iterator)
        while diskService != 0 {
            let serviceToProcess = diskService
            diskService = IOIteratorNext(iterator)
            
            if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, serviceToProcess),
               let descDict = DADiskCopyDescription(disk) as? [String: Any] {
                
                let isWhole = descDict[kDADiskDescriptionMediaWholeKey as String] as? Bool ?? false
                let protocolName = descDict[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
                let bsdName = descDict[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""

                let protocolChars = IORegistryEntrySearchCFProperty(
                    serviceToProcess,
                    kIOServicePlane,
                    "Protocol Characteristics" as CFString,
                    kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
                ) as? [String: Any]

                let isPhysical = DriveClassifier.isPhysicalDrive(
                    protocolCharacteristics: protocolChars,
                    deviceProtocol: protocolName,
                    bsdName: bsdName
                )
                
                if isWhole && isPhysical && !isSynthetic(service: serviceToProcess, protocolName: protocolName) {
                    let model = descDict[kDADiskDescriptionDeviceModelKey as String] as? String ?? "Unknown Model"
                    let sizeBytes = descDict[kDADiskDescriptionMediaSizeKey as String] as? UInt64 ?? 0
                    let daIsInternal = descDict[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false

                    let locationStr = (protocolChars?["Physical Interconnect Location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isInternal: Bool
                    if let loc = locationStr, !loc.isEmpty {
                        isInternal = loc.caseInsensitiveCompare("Internal") == .orderedSame
                    } else {
                        isInternal = daIsInternal
                    }
                    
                    let volumeNames = getVolumeNames(for: bsdName, session: session)
                    let (protocolType, mediumType, healthCapability) = ProtocolDetector.detect(bsdName: bsdName)
                    
                    let driveConnection = DriveClassifier.classify(
                        protocolCharacteristics: protocolChars,
                        deviceProtocol: protocolName,
                        isInternalHint: isInternal,
                        protocolType: protocolType
                    )

                    var usbVendorID: UInt16? = nil
                    var usbProductID: UInt16? = nil
                    if driveConnection == .usb || protocolName.contains("USB") {
                        let ids = getUSBIDs(service: serviceToProcess)
                        usbVendorID = ids.vid
                        usbProductID = ids.pid
                    }

                    let connection: Connection
                    switch driveConnection {
                    case .internalNVMe: connection = .nvmeInternal
                    case .internalAHCI: connection = .other
                    case .internalSATA: connection = .sata
                    case .thunderboltNVMe: connection = .nvmeExternal
                    case .usb: connection = .usb
                    case .other: connection = .other
                    }

                    let smartAvailability: SmartAvailability
                    switch healthCapability {
                    case .supported:
                        smartAvailability = .available
                    case .unsupported(let reason):
                        switch reason {
                        case .smartDisabled:
                            smartAvailability = .disabledOnDrive
                        case .usbBridge:
                            smartAvailability = .notSupportedByEnclosure
                        case .readFailed(let code):
                            let intCode = Int32(code) ?? -1
                            smartAvailability = .error(code: intCode)
                        default:
                            smartAvailability = .notSupportedByEnclosure
                        }
                    }

                    let interconnectStr = (protocolChars?["Physical Interconnect"] as? String) ?? ""
                    let isVirtual = protocolName == "Virtual Interface" || interconnectStr == "Virtual Interface"
                    let isDiskImage = protocolName == "Disk Image" || locationStr == "File"
                    
                    disks.append(PhysicalDisk(
                        bsdName: bsdName,
                        model: model.trimmingCharacters(in: .whitespacesAndNewlines),
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
                        smartAvailability: smartAvailability,
                        isVirtual: isVirtual,
                        isDiskImage: isDiskImage
                    ))
                }
            }
            IOObjectRelease(serviceToProcess)
        }
        
        return disks.sorted { $0.bsdName < $1.bsdName }
    }
    
    private static func isSynthetic(service: io_object_t, protocolName: String) -> Bool {
        var current = service
        IOObjectRetain(current)
        
        var hasBlockStorage = false
        var isAPFSContainer = false
        
        while current != 0 {
            if IOObjectConformsTo(current, "AppleAPFSContainerScheme") != 0 {
                isAPFSContainer = true
            }
            if IOObjectConformsTo(current, "IOBlockStorageDevice") != 0 {
                hasBlockStorage = true
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
        if isAPFSContainer { return true }
        if protocolName == "Virtual Interface" || protocolName == "Disk Image" { return true }
        return !hasBlockStorage
    }
    
    private static func getVolumeNames(for bsdName: String, session: DASession) -> [String] {
        var names: Set<String> = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            service = IOIteratorNext(iterator)
            
            var isChild = false
            var p = current
            IOObjectRetain(p)
            while p != 0 {
                if let name = IORegistryEntrySearchCFProperty(p, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault, 0) as? String {
                    if name == bsdName {
                        isChild = true
                        break
                    }
                }
                var parent: io_object_t = 0
                IORegistryEntryGetParentEntry(p, kIOServicePlane, &parent)
                IOObjectRelease(p)
                p = parent
            }
            if p != 0 { IOObjectRelease(p) }
            
            if isChild {
                if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, current) {
                    if let desc = DADiskCopyDescription(disk) as? [String: Any] {
                        if let volName = desc[kDADiskDescriptionVolumeNameKey as String] as? String, !volName.isEmpty {
                            names.insert(volName)
                        }
                    }
                }
            }
            IOObjectRelease(current)
        }
        
        return Array(names).sorted()
    }
    
    private static func getUSBIDs(service: io_object_t) -> (vid: UInt16?, pid: UInt16?) {
        var current = service
        IOObjectRetain(current)
        
        while current != 0 {
            if let vid = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault, 0) as? NSNumber,
               let pid = IORegistryEntrySearchCFProperty(current, kIOServicePlane, "idProduct" as CFString, kCFAllocatorDefault, 0) as? NSNumber {
                IOObjectRelease(current)
                return (vid.uint16Value, pid.uint16Value)
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
        return (nil, nil)
    }
}
