import SwiftUI
import AppKit
import DiskHealthCore

/// Couleurs de marque de l'anneau-jauge.
/// Réservées à l'anneau : le reste de l'interface garde les couleurs système.
enum AmanPalette {
    enum Level: Int, Comparable {
        case red = 0, orange = 1, water = 2
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var color: Color {
            switch self {
            case .water: return Color(hex: "#2E9FD6")
            case .orange: return Color(hex: "#E8A33D")
            case .red: return Color(hex: "#E5534B")
            }
        }
    }

    static let ink = Color(hex: "#0B2230")

    /// Pourcentage de durée de vie affichable, uniquement s'il est fourni par le disque.
    static func knownPercent(health: HealthAssessment, capability: HealthCapability) -> Int? {
        guard capability == .supported, let hp = health.healthPercent else { return nil }
        return hp
    }

    /// La plus grave entre la couleur du pourcentage (arrondi au 5 % inférieur) et celle de l'état.
    static func level(health: HealthAssessment, capability: HealthCapability) -> Level {
        var percentLevel = Level.water
        if let hp = knownPercent(health: health, capability: capability) {
            let rounded = (hp / 5) * 5
            if rounded <= 25 { percentLevel = .red }
            else if rounded <= 55 { percentLevel = .orange }
        }
        let statusLevel: Level
        switch health.status {
        case .good, .unknown: statusLevel = .water
        case .caution: statusLevel = .orange
        case .bad: statusLevel = .red
        }
        return min(percentLevel, statusLevel)
    }

    static func ringColor(health: HealthAssessment, capability: HealthCapability) -> Color {
        level(health: health, capability: capability).color
    }

    /// Fraction de l'arc : proportionnelle si connue, cercle complet sinon (jamais de pourcentage inventé).
    static func fraction(health: HealthAssessment, capability: HealthCapability) -> Double {
        if let hp = knownPercent(health: health, capability: capability) {
            return Double(hp) / 100.0
        }
        return 1.0
    }
}

/// Géométrie de l'anneau dans un repère 100 × 100.
enum AmanRingGeometry {
    static let center = CGPoint(x: 50, y: 50)
    static let radius: CGFloat = 26
    static let lineWidth: CGFloat = 10

    /// Goutte : `M50 37 C50 37 43.5 45.5 43.5 50 A6.5 6.5 0 0 0 56.5 50 C56.5 45.5 50 37 50 37 Z`.
    /// `flipped` : repère AppKit (origine en bas), pour le dessin en NSImage.
    static func dropPath(in rect: CGRect, flipped: Bool = false) -> CGPath {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: flipped ? rect.maxY - y * s : rect.minY + y * s)
        }
        let path = CGMutablePath()
        path.move(to: p(50, 37))
        path.addCurve(to: p(43.5, 50), control1: p(50, 37), control2: p(43.5, 45.5))
        // Demi-cercle inférieur de rayon 6,5 (arc SVG, balayage 0) de (43,5 ; 50) à (56,5 ; 50).
        path.addArc(center: p(50, 50), radius: 6.5 * s, startAngle: .pi, endAngle: 0, clockwise: !flipped)
        path.addCurve(to: p(50, 37), control1: p(56.5, 45.5), control2: p(50, 37))
        path.closeSubpath()
        return path
    }
}

/// Anneau-jauge compact (panneau de la barre des menus), sans fond.
struct MiniRingView: View {
    let health: HealthAssessment
    let capability: HealthCapability
    var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let s = min(canvasSize.width, canvasSize.height) / 100
            let r = AmanRingGeometry.radius * s
            let c = CGPoint(x: 50 * s, y: 50 * s)
            let w = AmanRingGeometry.lineWidth * s

            let track = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.stroke(track, with: .color(.secondary.opacity(0.35)), lineWidth: w)

            let fraction = AmanPalette.fraction(health: health, capability: capability)
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            ctx.stroke(arc, with: .color(AmanPalette.ringColor(health: health, capability: capability)), style: StrokeStyle(lineWidth: w, lineCap: .round))

            ctx.fill(Path(AmanRingGeometry.dropPath(in: rect)), with: .color(.primary))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Icône *template* de la barre des menus, dessinée en code (piste noire à 25 %).
enum MenuBarIconRenderer {
    static func image(fraction: Double, pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.width / 100
            let center = CGPoint(x: 50 * s, y: 50 * s)
            let r = AmanRingGeometry.radius * s
            ctx.setLineWidth(AmanRingGeometry.lineWidth * s)

            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            ctx.strokePath()

            // Départ en haut (12 h), sens horaire ; repère AppKit : angles trigonométriques.
            let clamped = max(0, min(1, fraction))
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * clamped, clockwise: true)
            ctx.strokePath()

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(AmanRingGeometry.dropPath(in: rect, flipped: true))
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Aman Disk"
        return image
    }
}
