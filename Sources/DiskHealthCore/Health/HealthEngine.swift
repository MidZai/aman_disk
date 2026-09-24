import Foundation

public enum HealthEngine {
    /// En dessous de ce pourcentage de durée de vie restante, le disque passe « À surveiller ».
    /// Même seuil que le passage au rouge de l'anneau (charte : rouge à 25 % et moins) : un anneau
    /// rouge à côté de « En bonne santé » serait contradictoire.
    public static let lowLifeThreshold = 25

    public static func evaluate(smart: NVMeSmartLog, identify: NVMeIdentify) -> HealthAssessment {
        var reasons: [String] = []
        var status: HealthStatus = .good

        // « Pourcentage utilisé » peut dépasser 100 : la durée de vie restante est alors de 0 %.
        let healthPercent = max(0, 100 - Int(smart.percentageUsed))

        // Défaillances (bits 0, 2, 3 et 4 de « Critical Warning »).
        let spareReason = L("Spare capacity has dropped below the manufacturer's threshold.", "La réserve de secours est passée sous le seuil du fabricant.")
        if (smart.criticalWarning & 0b0001_1101) != 0 {
            status = .bad
            if (smart.criticalWarning & 0b0000_0001) != 0 { reasons.append(spareReason) }
            if (smart.criticalWarning & 0b0000_0100) != 0 { reasons.append(L("Drive reliability is degraded (internal errors).", "La fiabilité du disque est dégradée (erreurs internes).")) }
            if (smart.criticalWarning & 0b0000_1000) != 0 { reasons.append(L("The drive has switched to read-only mode.", "Le disque est passé en lecture seule.")) }
            if (smart.criticalWarning & 0b0001_0000) != 0 { reasons.append(L("Volatile memory backup has failed.", "La sauvegarde de la mémoire volatile a échoué.")) }
        }
        if smart.availableSpare < smart.availableSpareThreshold {
            status = .bad
            if !reasons.contains(spareReason) { reasons.append(spareReason) }
        }
        // À surveiller. Ces constats sont listés même si l'état est déjà « Défaillance probable » :
        // l'utilisateur doit voir tout ce qui ne va pas, pas seulement le plus grave.
        var cautionReasons: [String] = []
        if smart.percentageUsed >= 100 {
            // Au-delà de 100 %, l'endurance garantie est dépassée, sans panne certaine pour autant.
            cautionReasons.append(L("The manufacturer's rated endurance is fully used up (\(smart.percentageUsed)% used).", "L'endurance prévue par le fabricant est entièrement consommée (\(smart.percentageUsed) % utilisés)."))
        } else if healthPercent <= lowLifeThreshold {
            cautionReasons.append(L("Remaining life is low (\(healthPercent)%).", "La durée de vie restante est faible (\(healthPercent) %)."))
        }
        if smart.mediaErrors > 0 {
            cautionReasons.append(L("\(Formatters.integer(smart.mediaErrors)) uncorrected data error(s) detected.", "\(Formatters.integer(smart.mediaErrors)) erreur(s) de données non corrigée(s) détectée(s)."))
        }
        if !cautionReasons.isEmpty {
            if status == .good { status = .caution }
            reasons += cautionReasons
        }

        // La température n'entre pas dans l'état de santé : une chauffe passagère (copie, test)
        // ferait basculer l'état et déclencher des alertes « changement d'état » à tort.
        // Elle a son propre indicateur et sa propre alerte (5 min au-dessus du seuil).

        if status == .good {
            reasons.append(L("No problems detected.", "Aucune anomalie détectée."))
        }

        return HealthAssessment(status: status, healthPercent: healthPercent, reasons: reasons)
    }
}
