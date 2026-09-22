import SwiftUI
import DiskHealthCore

struct HeroHeader: View {
    let physical: PhysicalDisk
    let assessment: HealthAssessment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(physical.model)
                .font(.system(size: 30, weight: .bold))
            
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(assessment.status))
                    .frame(width: 9, height: 9)
                
                Text(statusText(assessment.status))
                    .font(.body.weight(.semibold))
                
                let capacity = Formatters.bytes(physical.sizeBytes)
                Text("\(physical.model), \(capacity)")
                    .foregroundColor(.secondary)
            }
            
            let explanation = assessment.reasons.joined(separator: " ")
            Text(explanation)
                .foregroundColor(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: return Color(nsColor: .systemGreen)
        case .caution: return Color(nsColor: .systemOrange)
        case .bad: return Color(nsColor: .systemRed)
        case .unknown: return Color(nsColor: .systemGray)
        }
    }
    
    private func statusText(_ status: HealthStatus) -> String {
        switch status {
        case .good: return Strings.statusGood
        case .caution: return Strings.statusCaution
        case .bad: return Strings.statusBad
        case .unknown: return Strings.statusUnknown
        }
    }
}
