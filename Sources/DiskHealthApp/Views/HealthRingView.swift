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
        AmanPalette.fraction(health: health, capability: capability)
    }
    
    private var ringColor: Color {
        AmanPalette.ringColor(health: health, capability: capability)
    }
    
    private var accessibilityText: String {
        let status = health.status == .good ? "en bonne santé" : (health.status == .caution ? "attention" : "défaillance probable")
        if capability == .supported, let hp = health.healthPercent {
            return "Santé : \(status), \(hp) % de durée de vie"
        }
        return "Santé : \(status), durée de vie non fournie par ce disque"
    }
}
