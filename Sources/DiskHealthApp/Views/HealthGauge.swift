import SwiftUI
import DiskHealthCore

struct HealthGauge: View {
    let assessment: HealthAssessment
    
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ZStack {
            // Background track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
            
            // Foreground progress
            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(statusColor(assessment.status), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
            
            // Center content
            VStack(spacing: -2) {
                if let percent = assessment.healthPercent {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(percent)")
                            .font(.system(size: 54, weight: .semibold))
                            .monospacedDigit()
                        Text("%")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 54, weight: .semibold))
                }
                
                Text(Strings.health)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 224, height: 224)
        .onAppear {
            updateProgress(animate: true)
        }
        .onChange(of: assessment) { _, _ in
            updateProgress(animate: true)
        }
    }
    
    private func updateProgress(animate: Bool) {
        let targetValue = CGFloat(assessment.healthPercent ?? 0) / 100.0
        
        if reduceMotion || !animate {
            progress = targetValue
        } else {
            progress = 0
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) {
                progress = targetValue
            }
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
}
