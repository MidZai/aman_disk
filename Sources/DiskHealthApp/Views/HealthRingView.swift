import SwiftUI
import DiskHealthCore

/// Header ring gauge: ink background, track, life arc, drop.
/// Same geometry as the Dock and menu bar icons (`AmanRingGeometry`).
struct HealthRingView: View {
    let health: HealthAssessment
    let capability: HealthCapability

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let target = AmanPalette.fraction(health: health, capability: capability)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 100
            ZStack {
                Circle().fill(AmanPalette.ink)
                Circle()
                    .inset(by: (50 - AmanRingGeometry.radius) * scale)
                    .stroke(Color.white.opacity(0.16), lineWidth: AmanRingGeometry.lineWidth * scale)
                AmanArc(fraction: progress)
                    .stroke(AmanPalette.ringColor(health: health, capability: capability),
                            style: StrokeStyle(lineWidth: AmanRingGeometry.lineWidth * scale, lineCap: .round))
                Path(AmanRingGeometry.dropPath(in: CGRect(x: 0, y: 0, width: side, height: side)))
                    .fill(Color.white)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { animate(to: target) }
        // The reading changes (every 30 s): the arc follows without starting from zero.
        .onChange(of: target) { animate(to: target) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func animate(to value: Double) {
        if reduceMotion {
            progress = value
        } else {
            withAnimation(.easeOut(duration: 0.6)) { progress = value }
        }
    }

    private var accessibilityText: String {
        let status = health.status.localizedLabel
        if let hp = AmanPalette.knownPercent(health: health, capability: capability) {
            return L("\(status), \(hp)% life remaining", "\(status), \(hp) % de durée de vie restante")
        }
        return L("\(status), remaining life not reported by this drive", "\(status), durée de vie non fournie par ce disque")
    }
}

/// Arc starting at noon, clockwise, with the icon's length rule
/// (the round caps don't make the gauge look fuller than it is).
private struct AmanArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        let side = min(rect.width, rect.height)
        let scale = side / 100
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = AmanRingGeometry.radius * scale
        // `sweep` is defined in the 100 × 100 space: the angle doesn't depend on the scale.
        let sweep = AmanRingGeometry.sweep(fraction: fraction)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(-.pi / 2),
                    endAngle: .radians(-.pi / 2 + Double(sweep)), clockwise: false)
        return path
    }
}
