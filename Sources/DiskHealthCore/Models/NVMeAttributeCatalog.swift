import Foundation

public enum AttributeState: String, Codable {
    case normal
    case warning
    case critical
    case informational
}

public struct NVMeAttribute: Identifiable {
    public let id: UInt8
    public let name: String
    public let explanation: String
    public let displayValue: String
    public let rawValue: String
    public let state: AttributeState
    
    public init(id: UInt8, name: String, explanation: String, displayValue: String, rawValue: String, state: AttributeState) {
        self.id = id
        self.name = name
        self.explanation = explanation
        self.displayValue = displayValue
        self.rawValue = rawValue
        self.state = state
    }
}

public enum NVMeAttributeCatalog {
    private static func formatRaw(_ val: UInt64) -> String {
        return "0x\(String(format: "%02llX", val))"
    }
    
    public static func attributes(from log: NVMeSmartLog, identify: NVMeIdentify?) -> [NVMeAttribute] {
        var attrs: [NVMeAttribute] = []
        
        // 0x01: Avertissement critique
        let cwState: AttributeState
        if log.criticalWarning == 0 {
            cwState = .normal
        } else if log.criticalWarning == 1 << 1 {
            cwState = .warning // Only bit 1 active (temperature)
        } else {
            cwState = .critical
        }
        attrs.append(NVMeAttribute(id: 0x01, name: "Avertissement critique", explanation: "Indicateurs d'alerte envoyés par le contrôleur du disque. 0 signifie qu'aucune alerte n'est active.", displayValue: formatRaw(UInt64(log.criticalWarning)), rawValue: formatRaw(UInt64(log.criticalWarning)), state: cwState))
        
        // 0x02: Température composite
        let tempState: AttributeState
        let tStatus = TemperatureStatus.evaluate(temperatureCelsius: log.temperatureCelsius, identify: identify)
        switch tStatus {
        case .critical: tempState = .critical
        case .elevated: tempState = .warning
        default: tempState = .normal
        }
        let tempDisp = log.temperatureCelsius.map { "\($0) °C" } ?? "—"
        attrs.append(NVMeAttribute(id: 0x02, name: "Température composite", explanation: "Température globale du disque estimée par son contrôleur.", displayValue: tempDisp, rawValue: formatRaw(UInt64(log.compositeTemperatureKelvin)), state: tempState))
        
        // 0x03: Réserve disponible
        let resState: AttributeState
        if log.availableSpare < log.availableSpareThreshold {
            resState = .critical
        } else if log.availableSpare <= log.availableSpareThreshold + 10 && log.availableSpare < 100 && log.availableSpareThreshold < 90 {
            resState = .warning
        } else {
            resState = .normal
        }
        attrs.append(NVMeAttribute(id: 0x03, name: "Réserve disponible", explanation: "Part des blocs de secours encore disponibles pour remplacer les cellules usées. Elle diminue quand le disque vieillit.", displayValue: "\(log.availableSpare) %", rawValue: formatRaw(UInt64(log.availableSpare)), state: resState))
        
        // 0x04: Seuil de réserve
        attrs.append(NVMeAttribute(id: 0x04, name: "Seuil de réserve", explanation: "Niveau fixé par le fabricant. Si la réserve disponible passe en dessous, le disque signale un état critique.", displayValue: "\(log.availableSpareThreshold) %", rawValue: formatRaw(UInt64(log.availableSpareThreshold)), state: .informational))
        
        // 0x05: Pourcentage utilisé
        let pctState: AttributeState
        if log.percentageUsed >= 100 {
            pctState = .critical
        } else if log.percentageUsed >= 90 {
            pctState = .warning
        } else {
            pctState = .normal
        }
        attrs.append(NVMeAttribute(id: 0x05, name: "Pourcentage utilisé", explanation: "Estimation, par le fabricant, de la part de l'endurance déjà consommée. La valeur peut dépasser 100 % sans que le disque tombe en panne immédiatement.", displayValue: "\(log.percentageUsed) %", rawValue: formatRaw(UInt64(log.percentageUsed)), state: pctState))
        
        // 0x06: Données lues
        attrs.append(NVMeAttribute(id: 0x06, name: "Données lues", explanation: "Volume total de données lues depuis la fabrication du disque.", displayValue: Formatters.dataUnitsToBytesText(log.dataUnitsRead), rawValue: formatRaw(log.dataUnitsRead), state: .informational))
        
        // 0x07: Données écrites
        attrs.append(NVMeAttribute(id: 0x07, name: "Données écrites", explanation: "Volume total de données écrites depuis la fabrication. C'est le principal facteur d'usure d'un SSD.", displayValue: Formatters.dataUnitsToBytesText(log.dataUnitsWritten), rawValue: formatRaw(log.dataUnitsWritten), state: .informational))
        
        // 0x08: Commandes de lecture
        attrs.append(NVMeAttribute(id: 0x08, name: "Commandes de lecture", explanation: "Nombre de commandes de lecture traitées par le contrôleur.", displayValue: Formatters.integer(log.hostReadCommands), rawValue: formatRaw(log.hostReadCommands), state: .informational))
        
        // 0x09: Commandes d'écriture
        attrs.append(NVMeAttribute(id: 0x09, name: "Commandes d'écriture", explanation: "Nombre de commandes d'écriture traitées par le contrôleur.", displayValue: Formatters.integer(log.hostWriteCommands), rawValue: formatRaw(log.hostWriteCommands), state: .informational))
        
        // 0x0A: Temps d'activité du contrôleur
        attrs.append(NVMeAttribute(id: 0x0A, name: "Temps d'activité du contrôleur", explanation: "Temps, en minutes, pendant lequel le contrôleur a traité des commandes. Certains disques Apple indiquent toujours 0.", displayValue: Formatters.integer(log.controllerBusyTimeMinutes), rawValue: formatRaw(log.controllerBusyTimeMinutes), state: .informational))
        
        // 0x0B: Cycles d'allumage
        attrs.append(NVMeAttribute(id: 0x0B, name: "Cycles d'allumage", explanation: "Nombre de fois où le disque a été mis sous tension.", displayValue: Formatters.integer(log.powerCycles), rawValue: formatRaw(log.powerCycles), state: .informational))
        
        // 0x0C: Heures d'allumage
        attrs.append(NVMeAttribute(id: 0x0C, name: "Heures d'allumage", explanation: "Durée totale de fonctionnement du disque.", displayValue: Formatters.integer(log.powerOnHours), rawValue: formatRaw(log.powerOnHours), state: .informational))
        
        // 0x0D: Arrêts non propres
        attrs.append(NVMeAttribute(id: 0x0D, name: "Arrêts non propres", explanation: "Nombre de coupures d'alimentation sans arrêt normal (plantage, batterie vide, bouton maintenu). Une valeur non nulle est courante et généralement sans gravité.", displayValue: Formatters.integer(log.unsafeShutdowns), rawValue: formatRaw(log.unsafeShutdowns), state: .informational))
        
        // 0x0E: Erreurs média et intégrité
        let mediaState: AttributeState = log.mediaErrors > 0 ? .critical : .normal
        attrs.append(NVMeAttribute(id: 0x0E, name: "Erreurs média et intégrité", explanation: "Erreurs de données que le contrôleur n'a pas pu corriger. Toute valeur supérieure à 0 mérite d'être surveillée et de sauvegarder vos données.", displayValue: Formatters.integer(log.mediaErrors), rawValue: formatRaw(log.mediaErrors), state: mediaState))
        
        // 0x0F: Entrées du journal d'erreurs
        attrs.append(NVMeAttribute(id: 0x0F, name: "Entrées du journal d'erreurs", explanation: "Nombre d'entrées dans le journal d'erreurs du contrôleur. Une valeur non nulle est fréquente et n'indique pas forcément un problème.", displayValue: Formatters.integer(log.errorLogEntries), rawValue: formatRaw(log.errorLogEntries), state: .informational))
        
        return attrs
    }
}
