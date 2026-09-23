import SwiftUI
import DiskHealthCore

struct HealthRingView: View {
    let health: HealthAssessment
    let capability: HealthCapability
    
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        let pct = percentage
        
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 10)
                .frame(width: 52, height: 52)
            
            // Arc
            if pct > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
            }
            
            // Drop
            Path { path in
                path.move(to: CGPoint(x: 50, y: 37))
                path.addCurve(to: CGPoint(x: 43.5, y: 50), control1: CGPoint(x: 50, y: 37), control2: CGPoint(x: 43.5, y: 45.5))
                path.addArc(center: CGPoint(x: 50, y: 50), radius: 6.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                path.addCurve(to: CGPoint(x: 50, y: 37), control1: CGPoint(x: 56.5, y: 45.5), control2: CGPoint(x: 50, y: 37))
                path.closeSubpath()
            }
            .fill(Color.white)
            // The path is defined in a 100x100 coordinate space
            .scaleEffect(0.96) // (96 / 100)
        }
        .frame(width: 96, height: 96)
        .background(Color(hex: "#0B2230"))
        .clipShape(Circle())
        .onAppear {
            if reduceMotion {
                progress = pct
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    progress = pct
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
    
    private var percentage: Double {
        if case .unsupported(let reason) = capability, reason == .smartDisabled {
            return 1.0
        }
        if capability == .supported {
            if let hp = health.healthPercent {
                return Double(hp) / 100.0
            }
        }
        return 1.0
    }
    
    private var ringColor: Color {
        let baseColor: Color
        if capability == .supported, let hp = health.healthPercent {
            let rounded = (hp / 5) * 5
            if rounded <= 25 {
                baseColor = Color(hex: "#E5534B")
            } else if rounded <= 55 {
                baseColor = Color(hex: "#E8A33D")
            } else {
                baseColor = Color(hex: "#2E9FD6")
            }
        } else {
            baseColor = Color(hex: "#2E9FD6")
        }
        
        let statusColor: Color
        switch health.status {
        case .good: statusColor = Color(hex: "#2E9FD6")
        case .caution: statusColor = Color(hex: "#E8A33D")
        case .bad: statusColor = Color(hex: "#E5534B")
        case .unknown: statusColor = baseColor
        }
        
        // Ensure toHex is not used since it's removed, we'll just evaluate worst based on enum-like values
        // We know the colors, we can assign a score
        func score(_ color: Color) -> Int {
            if color == Color(hex: "#E5534B") { return 0 }
            if color == Color(hex: "#E8A33D") { return 1 }
            return 2
        }
        let scoreBase = score(baseColor)
        let scoreStatus = score(statusColor)
        let worst = min(scoreBase, scoreStatus)
        if worst == 0 { return Color(hex: "#E5534B") }
        if worst == 1 { return Color(hex: "#E8A33D") }
        return Color(hex: "#2E9FD6")
    }
    
    private var accessibilityText: String {
        let status = health.status == .good ? "en bonne santé" : (health.status == .caution ? "attention" : "défaillance probable")
        if capability == .supported, let hp = health.healthPercent {
            return "Santé : \(status), \(hp) % de durée de vie"
        }
        return "Santé : \(status), durée de vie non fournie par ce disque"
    }
}
