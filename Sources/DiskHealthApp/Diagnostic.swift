import Foundation
import DiskHealthCore

struct Diagnostic: Codable {
    let usbVendorId: String
    let usbProductId: String
    let model: String
    let macosVersion: String
    let architecture: String
    
    init(physical: PhysicalDisk) {
        self.usbVendorId = physical.usbVendorID.map { String(format: "0x%04X", $0) } ?? "Unknown"
        self.usbProductId = physical.usbProductID.map { String(format: "0x%04X", $0) } ?? "Unknown"
        self.model = physical.model
        
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.macosVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        
        #if arch(arm64)
        self.architecture = "arm64"
        #elseif arch(x86_64)
        self.architecture = "x86_64"
        #else
        self.architecture = "unknown"
        #endif
    }
}
