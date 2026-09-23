import Foundation

public enum ATARole: Equatable {
    case temperature
    case powerOnHours
    case powerCycles
    case unsafeShutdowns
    case hostWritesBytes(multiplier: UInt64)
    case hostReadsBytes(multiplier: UInt64)
    case lifeRemainingPercentNormalized
    case reallocated
    case pending
    case uncorrectable
    case none
}

public struct AttributeOverride: Equatable {
    public let name: String
    public let explanation: String
    public let role: ATARole
}

public struct ATAProfile {
    public let name: String
    public let matches: (String) -> Bool
    public let attributes: [UInt8: AttributeOverride]
}

public enum ATACatalog {
    public static let genericAttributes: [UInt8: AttributeOverride] = [
        0x01: AttributeOverride(name: "Taux d'erreurs de lecture", explanation: "Erreurs rencontrées lors de la lecture. La valeur brute n'est pas comparable d'un fabricant à l'autre.", role: .none),
        0x03: AttributeOverride(name: "Temps de démarrage du moteur", explanation: "Temps nécessaire aux plateaux pour atteindre leur vitesse (disques durs).", role: .none),
        0x04: AttributeOverride(name: "Démarrages et arrêts du moteur", explanation: "Nombre de démarrages du moteur (disques durs).", role: .none),
        0x05: AttributeOverride(name: "Secteurs réalloués", explanation: "Secteurs défectueux remplacés par des secteurs de réserve. Une valeur qui augmente indique une dégradation du support.", role: .reallocated),
        0x07: AttributeOverride(name: "Taux d'erreurs de positionnement", explanation: "Erreurs de positionnement des têtes (disques durs). Valeur brute propre au fabricant.", role: .none),
        0x09: AttributeOverride(name: "Heures d'allumage", explanation: "Durée totale de fonctionnement du disque.", role: .powerOnHours),
        0x0A: AttributeOverride(name: "Tentatives de démarrage", explanation: "Nouvelles tentatives nécessaires pour démarrer le moteur (disques durs).", role: .none),
        0x0C: AttributeOverride(name: "Cycles d'allumage", explanation: "Nombre de mises sous tension du disque.", role: .powerCycles),
        0xAB: AttributeOverride(name: "Échecs de programmation", explanation: "Échecs d'écriture dans les cellules de mémoire flash.", role: .none),
        0xAC: AttributeOverride(name: "Échecs d'effacement", explanation: "Échecs d'effacement des cellules de mémoire flash.", role: .none),
        0xAD: AttributeOverride(name: "Nivellement de l'usure", explanation: "Indicateur de l'usure des cellules de mémoire flash. Interprétation propre au fabricant.", role: .none),
        0xAE: AttributeOverride(name: "Pertes d'alimentation inattendues", explanation: "Coupures de courant sans arrêt normal.", role: .unsafeShutdowns),
        0xB1: AttributeOverride(name: "Nivellement de l'usure", explanation: "Sur de nombreux SSD, la valeur normalisée indique la durée de vie restante estimée.", role: .none),
        0xB3: AttributeOverride(name: "Blocs de réserve utilisés", explanation: "Blocs de réserve déjà utilisés pour remplacer des blocs usés.", role: .none),
        0xB5: AttributeOverride(name: "Échecs de programmation", explanation: "Échecs d'écriture dans la mémoire flash.", role: .none),
        0xB6: AttributeOverride(name: "Échecs d'effacement", explanation: "Échecs d'effacement dans la mémoire flash.", role: .none),
        0xB7: AttributeOverride(name: "Rétrogradations de l'interface", explanation: "Nombre de fois où la liaison SATA a dû réduire sa vitesse.", role: .none),
        0xB8: AttributeOverride(name: "Erreurs de bout en bout", explanation: "Erreurs de transfert détectées entre le cache et le support.", role: .none),
        0xBB: AttributeOverride(name: "Erreurs non corrigibles signalées", explanation: "Erreurs de lecture que le disque n'a pas pu corriger.", role: .uncorrectable),
        0xBE: AttributeOverride(name: "Température (flux d'air)", explanation: "Température mesurée par le disque.", role: .temperature),
        0xC0: AttributeOverride(name: "Arrêts non propres", explanation: "Coupures d'alimentation sans arrêt normal (ou rétractions d'urgence des têtes sur un disque dur).", role: .unsafeShutdowns),
        0xC1: AttributeOverride(name: "Cycles de chargement des têtes", explanation: "Nombre de chargements et déchargements des têtes (disques durs).", role: .none),
        0xC2: AttributeOverride(name: "Température", explanation: "Température du disque.", role: .temperature),
        0xC3: AttributeOverride(name: "Erreurs corrigées par ECC", explanation: "Erreurs corrigées par le code de correction. Valeur propre au fabricant.", role: .none),
        0xC4: AttributeOverride(name: "Événements de réallocation", explanation: "Nombre d'opérations de réallocation effectuées.", role: .none),
        0xC5: AttributeOverride(name: "Secteurs en attente", explanation: "Secteurs instables en attente de réallocation. Une valeur non nulle mérite une sauvegarde rapide.", role: .pending),
        0xC6: AttributeOverride(name: "Secteurs non corrigibles", explanation: "Secteurs illisibles détectés lors des vérifications hors ligne.", role: .uncorrectable),
        0xC7: AttributeOverride(name: "Erreurs CRC de l'interface", explanation: "Erreurs de transmission sur la liaison. Souvent liées à la connexion, rarement au support lui-même.", role: .none),
        0xE7: AttributeOverride(name: "Durée de vie restante du SSD", explanation: "Durée de vie restante estimée par le fabricant.", role: .lifeRemainingPercentNormalized),
        0xE8: AttributeOverride(name: "Réserve disponible", explanation: "Part de la réserve de blocs encore disponible.", role: .none),
        0xE9: AttributeOverride(name: "Indicateur d'usure du support", explanation: "Usure de la mémoire flash ; la valeur normalisée diminue avec l'usage.", role: .lifeRemainingPercentNormalized),
        0xF1: AttributeOverride(name: "Total des données écrites", explanation: "Volume total écrit par l'ordinateur.", role: .hostWritesBytes(multiplier: 512)),
        0xF2: AttributeOverride(name: "Total des données lues", explanation: "Volume total lu par l'ordinateur.", role: .hostReadsBytes(multiplier: 512))
    ]

    public static let genericProfile = ATAProfile(
        name: "GenericATA",
        matches: { _ in true },
        attributes: [:]
    )

    // Attribute names cross-checked with smartmontools drivedb.h and real smartctl output.
    public static let appleSMFamilyProfile = ATAProfile(
        name: "AppleSMFamily",
        matches: { model in
            model.range(of: "^APPLE SSD (SD|SM|TS)\\d{4}[EFG]$", options: .regularExpression) != nil
        },
        attributes: [
            0x01: AttributeOverride(name: genericAttributes[0x01]!.name, explanation: genericAttributes[0x01]!.explanation + "\n\nNom technique : Raw_Read_Error_Rate", role: .none),
            0x05: AttributeOverride(name: genericAttributes[0x05]!.name, explanation: genericAttributes[0x05]!.explanation + "\n\nNom technique : Reallocated_Sector_Ct", role: .reallocated),
            0x09: AttributeOverride(name: genericAttributes[0x09]!.name, explanation: genericAttributes[0x09]!.explanation + "\n\nNom technique : Power_On_Hours", role: .powerOnHours),
            0x0C: AttributeOverride(name: genericAttributes[0x0C]!.name, explanation: genericAttributes[0x0C]!.explanation + "\n\nNom technique : Power_Cycle_Count", role: .powerCycles),
            0xA9: AttributeOverride(name: "Attribut propre au fabricant", explanation: "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement.\n\nNom technique : Unknown_Apple_Attrib", role: .none),
            0xAD: AttributeOverride(name: "Nivellement de l'usure", explanation: "Indicateur d'usure du support.\n\nNom technique : Wear_Leveling_Count", role: .none),
            0xAE: AttributeOverride(name: "Total des données lues", explanation: "Total des données lues par l'ordinateur.\n\nNom technique : Host_Reads_MiB", role: .hostReadsBytes(multiplier: 1048576)),
            0xAF: AttributeOverride(name: "Total des données écrites", explanation: "Total des données écrites par l'ordinateur.\n\nNom technique : Host_Writes_MiB", role: .hostWritesBytes(multiplier: 1048576)),
            0xC0: AttributeOverride(name: genericAttributes[0xC0]!.name, explanation: genericAttributes[0xC0]!.explanation + "\n\nNom technique : Power-Off_Retract_Count", role: .unsafeShutdowns),
            0xC2: AttributeOverride(name: genericAttributes[0xC2]!.name, explanation: genericAttributes[0xC2]!.explanation + "\n\nNom technique : Temperature_Celsius", role: .temperature),
            0xC5: AttributeOverride(name: genericAttributes[0xC5]!.name, explanation: genericAttributes[0xC5]!.explanation + "\n\nNom technique : Current_Pending_Sector", role: .pending),
            0xC7: AttributeOverride(name: genericAttributes[0xC7]!.name, explanation: genericAttributes[0xC7]!.explanation + "\n\nNom technique : UDMA_CRC_Error_Count", role: .none),
            0xF0: AttributeOverride(name: "Attribut propre au fabricant", explanation: "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement.\n\nNom technique : Unknown_SSD_Attribute", role: .none)
        ]
    )
    
    public static let samsungProfile = ATAProfile(
        name: "Samsung",
        matches: { model in model.starts(with: "Samsung") },
        attributes: [
            0xB1: AttributeOverride(name: "Nivellement de l'usure", explanation: "Sur de nombreux SSD, la valeur normalisée indique la durée de vie restante estimée.", role: .lifeRemainingPercentNormalized)
        ]
    )


    public static let profiles = [appleSMFamilyProfile, samsungProfile] // Ordered by priority

    public static func profile(for model: String) -> ATAProfile {
        for profile in profiles {
            if profile.matches(model) {
                return profile
            }
        }
        return genericProfile
    }

    public static func attributeInfo(id: UInt8, profile: ATAProfile) -> AttributeOverride {
        if let override = profile.attributes[id] {
            return override
        }
        if let generic = genericAttributes[id] {
            return generic
        }
        return AttributeOverride(name: "Attribut propre au fabricant", explanation: "Attribut spécifique à ce modèle. Sa signification n'est pas documentée publiquement.", role: .none)
    }
}

public extension ATASmartAttribute {
    func value(for role: ATARole) -> UInt64? {
        switch role {
        case .temperature:
            let temp = raw[0]
            if temp >= 1 && temp <= 99 {
                return UInt64(temp)
            }
            return nil
        case .powerOnHours:
            var val: UInt64 = 0
            for i in 0..<4 {
                val |= (UInt64(raw[i]) << (i * 8))
            }
            return val
        case .hostWritesBytes(let multiplier):
            return rawValue * multiplier
        case .hostReadsBytes(let multiplier):
            return rawValue * multiplier
        case .lifeRemainingPercentNormalized:
            return UInt64(current)
        case .powerCycles, .unsafeShutdowns, .reallocated, .pending, .uncorrectable:
            return rawValue
        case .none:
            return nil
        }
    }
}
