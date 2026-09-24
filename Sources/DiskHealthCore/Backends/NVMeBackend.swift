import Foundation

public struct NVMeBackend: HealthBackend {
    public static func canHandle(bsdName: String) -> Bool {
        let (protocolType, _, _) = ProtocolDetector.detect(bsdName: bsdName)
        return protocolType == .nvme
    }
    
    public static func read(bsdName: String) throws -> DiskHealthSnapshot {
        try read(bsdName: bsdName, knownIdentify: nil)
    }

    /// `knownIdentify` : données Identify d'une lecture précédente. Elles ne changent pas
    /// (modèle, numéro de série, seuils) : seule la lecture du journal SMART est alors refaite.
    public static func read(bsdName: String, knownIdentify: NVMeIdentify?) throws -> DiskHealthSnapshot {
        if let identify = knownIdentify {
            guard let smartLog = NVMeSmartParser.parse(try NVMeReader.readSmartLog(bsdName: bsdName)) else {
                throw NVMeReadError.readFailed
            }
            return .nvme(smartLog, identify)
        }
        let raw = try NVMeReader.readAll(bsdName: bsdName)
        guard let smartLog = NVMeSmartParser.parse(raw.smart),
              let identify = NVMeIdentifyParser.parse(raw.identify) else {
            throw NVMeReadError.readFailed
        }
        return .nvme(smartLog, identify)
    }
}
