import SwiftUI
import AppKit
import DiskHealthCore

/// Brand colors of the ring gauge.
/// Reserved for the ring: the rest of the interface keeps the system colors.
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

    /// Life percentage that can be shown, only if the drive reports it.
    static func knownPercent(health: HealthAssessment, capability: HealthCapability) -> Int? {
        guard capability == .supported, let hp = health.healthPercent else { return nil }
        return hp
    }

    /// The more severe of the percentage color (rounded down to 5%) and the status color.
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

    /// Fraction of the arc: proportional if known, a full circle otherwise (never a made-up percentage).
    static func fraction(health: HealthAssessment, capability: HealthCapability) -> Double {
        if let hp = knownPercent(health: health, capability: capability) {
            return Double(hp) / 100.0
        }
        return 1.0
    }
}

/// Geometry of the ring in a 100 × 100 coordinate space.
enum AmanRingGeometry {
    static let center = CGPoint(x: 50, y: 50)
    static let radius: CGFloat = 26
    static let lineWidth: CGFloat = 10
    
    /// Angle swept by the arc: length = p × 2π × 26 − 10 (compensates for the round caps); full circle at 100%.
    static func sweep(fraction: Double) -> CGFloat {
        let f = CGFloat(max(0, min(1, fraction)))
        if f >= 1 { return 2 * .pi }
        return max(0.001, f * 2 * .pi * radius - lineWidth) / radius
    }

    /// Drop: `M50 37 C50 37 43.5 45.5 43.5 50 A6.5 6.5 0 0 0 56.5 50 C56.5 45.5 50 37 50 37 Z`.
    /// `flipped`: AppKit coordinates (origin at the bottom), for drawing into an NSImage.
    static func dropPath(in rect: CGRect, flipped: Bool = false) -> CGPath {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: flipped ? rect.maxY - y * s : rect.minY + y * s)
        }
        let path = CGMutablePath()
        path.move(to: p(50, 37))
        path.addCurve(to: p(43.5, 50), control1: p(50, 37), control2: p(43.5, 45.5))
        // Lower half-circle of radius 6.5 (SVG arc, sweep 0) from (43.5, 50) to (56.5, 50).
        path.addArc(center: p(50, 50), radius: 6.5 * s, startAngle: .pi, endAngle: 0, clockwise: !flipped)
        path.addCurve(to: p(50, 37), control1: p(56.5, 45.5), control2: p(50, 37))
        path.closeSubpath()
        return path
    }
}

/// Compact ring gauge (menu bar panel), without a background.
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
            arc.addArc(center: c, radius: r, startAngle: .radians(-.pi / 2), endAngle: .radians(-.pi / 2 + AmanRingGeometry.sweep(fraction: fraction)), clockwise: false)
            ctx.stroke(arc, with: .color(AmanPalette.ringColor(health: health, capability: capability)), style: StrokeStyle(lineWidth: w, lineCap: .round))

            ctx.fill(Path(AmanRingGeometry.dropPath(in: rect)), with: .color(.primary))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// *Template* menu bar icon, drawn in code (black track at 25%).
enum MenuBarIconRenderer {
    /// The menu bar label is redrawn on every reading: the image is only recreated
    /// when the gauge changes (to the nearest percent).
    @MainActor private static var cache: (percent: Int, image: NSImage)?

    @MainActor
    static func cachedImage(fraction: Double) -> NSImage {
        let percent = Int((fraction * 100).rounded())
        if let cache, cache.percent == percent { return cache.image }
        let image = image(fraction: Double(percent) / 100)
        cache = (percent, image)
        return image
    }

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

            // Starts at the top (12 o'clock), clockwise; AppKit coordinates: trigonometric angles.
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - AmanRingGeometry.sweep(fraction: fraction), clockwise: true)
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

extension Color {
    /// Brand color, in sRGB: “#RRGGBB” or “#AARRGGBB”.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch digits.count {
        case 6: (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8: (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
