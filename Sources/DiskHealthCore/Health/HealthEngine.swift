import Foundation

public enum HealthEngine {
    public static func evaluate(smart: NVMeSmartLog, identify: NVMeIdentify) -> HealthAssessment {
        var reasons: [String] = []
        var status: HealthStatus = .good
        
        let healthPercentValue = max(0, 100 - Int(smart.percentageUsed))
        let healthPercent: Int? = (smart.percentageUsed <= 150) ? healthPercentValue : 0
        
        // Critical failures
        if (smart.criticalWarning & 0b0001_1101) != 0 {
            status = .bad
            if (smart.criticalWarning & 0b0000_0001) != 0 {
                reasons.append("La réserve de secours est passée sous le seuil du fabricant.")
            }
            if (smart.criticalWarning & 0b0000_0100) != 0 {
                reasons.append("La fiabilité du disque est dégradée.")
            }
            if (smart.criticalWarning & 0b0000_1000) != 0 {
                reasons.append("Le disque est passé en mode lecture seule.")
            }
            if (smart.criticalWarning & 0b0001_0000) != 0 {
                reasons.append("La sauvegarde de la mémoire volatile a échoué.")
            }
        }
        
        if smart.availableSpare < smart.availableSpareThreshold {
            if status != .bad {
                status = .bad
            }
            if !reasons.contains("La réserve de secours est passée sous le seuil du fabricant.") {
                reasons.append("La réserve de secours est passée sous le seuil du fabricant.")
            }
        }
        
        // Caution failures
        var isCaution = false
        if status != .bad {
            if smart.percentageUsed >= 90 {
                isCaution = true
                reasons.append("L'usure du disque a atteint ou dépassé 90 %.")
            }
            if smart.mediaErrors > 0 {
                isCaution = true
                reasons.append("Des erreurs de média ou d'intégrité ont été détectées.")
            }
            if (smart.criticalWarning & 0b0000_0010) != 0 {
                isCaution = true
                reasons.append("La température a dépassé un seuil critique selon le fabricant.")
            }
            if identify.warningTempKelvin > 0 && smart.compositeTemperatureKelvin >= identify.warningTempKelvin {
                isCaution = true
                reasons.append("La température actuelle dépasse le seuil d'avertissement.")
            }
            
            if isCaution {
                status = .caution
            }
        }
        
        if status == .good {
            reasons.append("Aucune anomalie détectée.")
        }
        
        return HealthAssessment(status: status, healthPercent: healthPercent, reasons: reasons)
    }
}
