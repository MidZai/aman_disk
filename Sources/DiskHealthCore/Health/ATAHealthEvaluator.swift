import Foundation

public enum ATAHealthEvaluator {
    public static func evaluate(snapshot: ATASmartSnapshot) -> HealthAssessment {
        let profile = ATACatalog.profile(for: snapshot.model)
        
        var reasons = [String]()
        var status = HealthStatus.good
        var lifeRemaining: Int? = nil
        var temperature: Int? = nil
        
        // Find life remaining
        for attr in snapshot.attributes {
            let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
            if info.role == .lifeRemainingPercentNormalized {
                let current = Int(attr.current)
                lifeRemaining = max(0, min(100, current))
            }
            if info.role == .temperature {
                if let temp = attr.value(for: .temperature) {
                    temperature = Int(temp)
                }
            }
        }
        
        // Rule 1: .bad
        if snapshot.thresholdExceeded {
            status = .bad
            reasons.append("Le statut S.M.A.R.T. global indique une défaillance imminente.")
        }
        
        for attr in snapshot.attributes {
            if attr.threshold > 0 && attr.current <= attr.threshold {
                status = .bad
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                reasons.append("L'attribut « \(info.name) » est passé sous son seuil critique.")
            }
        }
        
        // Rule 2: .caution (if not bad)
        if status != .bad {
            for attr in snapshot.attributes {
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                if info.role == .reallocated || info.role == .pending || info.role == .uncorrectable {
                    if let raw = attr.value(for: info.role), raw > 0 {
                        status = .caution
                        reasons.append("\(raw) \(info.name.lowercased()) détecté(s).")
                    }
                }
            }
            
            if let life = lifeRemaining, life <= 10 {
                status = .caution
                reasons.append("La durée de vie restante estimée est très faible (\(life) %).")
            }
            
            if let temp = temperature {
                let isSSD = snapshot.rotationRate == 1
                if (isSSD && temp >= 60) || (!isSSD && temp >= 55) {
                    status = .caution
                    reasons.append("La température est élevée (\(temp) °C).")
                }
            }
        }
        
        if status == .good {
            reasons.append("Le disque est en bon état.")
        }
        
        return HealthAssessment(status: status, healthPercent: lifeRemaining, reasons: reasons)
    }
}
