import SwiftUI
import DiskHealthCore

struct HealthHalo: View {
    let status: HealthStatus
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                statusColor(status).opacity(0.18),
                Color.clear
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 380
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: status)
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
