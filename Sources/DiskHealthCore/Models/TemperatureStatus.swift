import Foundation

public enum TemperatureStatus: String, Codable {
    case normal
    case elevated
    case critical
    case unknown

    public var label: String {
        switch self {
        case .normal: return L("Normal", "Normale")
        case .elevated: return L("High", "Élevée")
        case .critical: return L("Critical", "Critique")
        case .unknown: return L("Unknown", "Inconnue")
        }
    }

    /// Seuils génériques (utilisés quand le disque n'annonce pas les siens) :
    /// SSD 60 / 70 °C, disque dur 55 / 65 °C. Mêmes valeurs que les alertes et l'arrêt du test.
    public static func genericThresholds(isRotational: Bool) -> (warning: Int, critical: Int) {
        isRotational ? (55, 65) : (60, 70)
    }

    public static func evaluate(temperatureCelsius tempC: Int?, identify: NVMeIdentify?, isRotational: Bool = false) -> TemperatureStatus {
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

        let limits = genericThresholds(isRotational: isRotational)
        if tempC >= limits.critical { return .critical }
        if tempC >= limits.warning { return .elevated }
        return .normal
    }
}
