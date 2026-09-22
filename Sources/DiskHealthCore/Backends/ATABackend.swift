import Foundation

public struct ATABackend: HealthBackend {
    public static func canHandle(bsdName: String) -> Bool {
        let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
        return protocolType == .ata
    }
    
    public static func read(bsdName: String) throws -> DiskHealthSnapshot {
        let smartData = try ATAReader.readSmartData(bsdName: bsdName)
        let thresholdsData = try ATAReader.readSmartThresholds(bsdName: bsdName)
        let identifyData = try ATAReader.readIdentify(bsdName: bsdName)
        let status = try ATAReader.readSmartStatus(bsdName: bsdName)
        
        guard let snapshot = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: status) else {
            throw ATAReadError.invalidArguments // or readFailed
        }
        
        return .ata(snapshot)
    }
}
