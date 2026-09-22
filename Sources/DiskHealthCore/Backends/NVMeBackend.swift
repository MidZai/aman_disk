import Foundation

public struct NVMeBackend: HealthBackend {
    public static func canHandle(bsdName: String) -> Bool {
        let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
        return protocolType == .nvme
    }
    
    public static func read(bsdName: String) throws -> DiskHealthSnapshot {
        let smartData = try NVMeReader.readSmartLog(bsdName: bsdName)
        let identifyData = try NVMeReader.readIdentify(bsdName: bsdName)
        
        guard let smartLog = NVMeSmartParser.parse(smartData),
              let identify = NVMeIdentifyParser.parse(identifyData) else {
            throw NVMeReadError.readFailed
        }
        
        return .nvme(smartLog, identify)
    }
}
