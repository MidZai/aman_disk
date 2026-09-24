import SwiftUI
import DiskHealthCore

/// Anneau-jauge de l'en-tête : fond encre, piste, arc de durée de vie, goutte.
/// Même géométrie que l'icône du Dock et de la barre des menus (`AmanRingGeometry`).
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
        // Le relevé change (toutes les 30 s) : l'arc suit, sans repartir de zéro.
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

/// Arc qui part de midi, dans le sens horaire, avec la règle de longueur de l'icône
/// (les bouts arrondis ne font pas paraître la jauge plus remplie qu'elle ne l'est).
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
        // `sweep` est défini dans le repère 100 × 100 : l'angle ne dépend pas de l'échelle.
        let sweep = AmanRingGeometry.sweep(fraction: fraction)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(-.pi / 2),
                    endAngle: .radians(-.pi / 2 + Double(sweep)), clockwise: false)
        return path
    }
}
