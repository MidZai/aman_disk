import Foundation

public enum TemperatureStatus: String, Codable {
    case normal
    case elevated
    case critical
    case unknown
    
    public var label: String {
        switch self {
        case .normal: return "Normale"
        case .elevated: return "Élevée"
        case .critical: return "Critique"
        case .unknown: return "Inconnue"
        }
    }
    
    public static func evaluate(temperatureCelsius tempC: Int?, identify: NVMeIdentify?) -> TemperatureStatus {
        guard let tempC = tempC else { return .unknown }
        
        if let identify = identify {
            let criticalC = identify.criticalTempKelvin > 0 ? Int(identify.criticalTempKelvin) - 273 : nil
            let warningC = identify.warningTempKelvin > 0 ? Int(identify.warningTempKelvin) - 273 : nil
            
            if let crit = criticalC, tempC >= crit {
                return .critical
            } else if let warn = warningC, tempC >= warn {
                return .elevated
            }
            
            if criticalC != nil || warningC != nil {
                return .normal
            }
        }
        
        if tempC >= 70 { return .critical }
        if tempC >= 60 { return .elevated }
        return .normal
    }
}
