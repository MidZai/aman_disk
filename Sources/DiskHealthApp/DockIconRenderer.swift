import AppKit
import SwiftUI
import DiskHealthCore

/// Icône vivante du Dock : fond squircle encre, piste blanche à 16 %, arc coloré, goutte blanche.
/// Reproduit `etats-sante/icone-app-svg/aman-XXX.svg` du kit de marque.
enum DockIconRenderer {
    /// Ce qui détermine l'icône : on ne redessine que si l'une de ces valeurs change.
    struct State: Equatable {
        /// Pourcentage de durée de vie arrondi à 1 %, nil si le disque ne le fournit pas.
        let percent: Int?
        let level: AmanPalette.Level

        init(percent: Int?, level: AmanPalette.Level) {
            self.percent = percent
            self.level = level
        }

        init(health: HealthAssessment, capability: HealthCapability) {
            let known = AmanPalette.knownPercent(health: health, capability: capability)
            self.percent = known
            if known != nil {
                self.level = AmanPalette.level(health: health, capability: capability)
            } else {
                // Pourcentage inconnu : jauge figée à 80 % (icône officielle), couleur de l'état seulement.
                self.level = AmanPalette.level(health: HealthAssessment(status: health.status, healthPercent: nil, reasons: []), capability: capability)
            }
        }

        /// Pourcentage inconnu et état bon : c'est exactement l'icône officielle.
        var isOfficialIcon: Bool { percent == nil && level == .water }
        /// Arc dessiné : le pourcentage réel, ou 80 % (icône officielle) s'il est inconnu.
        var drawnPercent: Int { percent ?? 80 }
    }

    static let canvas: CGFloat = 1024

    static func cgColor(_ level: AmanPalette.Level) -> CGColor {
        switch level {
        case .water: return CGColor(srgbRed: 0x2E / 255, green: 0x9F / 255, blue: 0xD6 / 255, alpha: 1)
        case .orange: return CGColor(srgbRed: 0xE8 / 255, green: 0xA3 / 255, blue: 0x3D / 255, alpha: 1)
        case .red: return CGColor(srgbRed: 0xE5 / 255, green: 0x53 / 255, blue: 0x4B / 255, alpha: 1)
        }
    }

    /// Squircle du kit : superellipse d'exposant 5, centre (512, 512), demi-côté 412.
    static func squirclePath() -> CGPath {
        let path = CGMutablePath()
        let c: CGFloat = 512, r: CGFloat = 412, n: CGFloat = 5
        let steps = 720
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let cosT = cos(t), sinT = sin(t)
            let x = c + r * (cosT < 0 ? -1 : 1) * pow(abs(cosT), 2 / n)
            let y = c + r * (sinT < 0 ? -1 : 1) * pow(abs(sinT), 2 / n)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    /// Rendu 1024 × 1024 (repère SVG, origine en haut à gauche).
    static func cgImage(state: State) -> CGImage? {
        let size = Int(canvas)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Repère SVG : y vers le bas.
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy(x: 1, y: -1)

        // Fond encre avec l'ombre du kit (dy 10, flou 10, noir 30 %).
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
        ctx.setFillColor(CGColor(srgbRed: 0x0B / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 1))
        ctx.addPath(squirclePath())
        ctx.fillPath()
        ctx.restoreGState()

        // Glyphe : translate(100 100) scale(8.24).
        ctx.translateBy(x: 100, y: 100)
        ctx.scaleBy(x: 8.24, y: 8.24)
        let center = AmanRingGeometry.center
        let r = AmanRingGeometry.radius
        let w = AmanRingGeometry.lineWidth

        ctx.setLineWidth(w)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ctx.strokePath()

        let p = max(0, min(100, state.drawnPercent))
        ctx.setStrokeColor(cgColor(state.level))
        if p >= 100 {
            ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            ctx.strokePath()
        } else if p > 0 {
            let sweep = AmanRingGeometry.sweep(fraction: Double(p) / 100)
            let start = -CGFloat.pi / 2
            ctx.setLineCap(.round)
            // Repère y vers le bas : angle croissant = sens horaire à l'écran.
            ctx.addArc(center: center, radius: r, startAngle: start, endAngle: start + sweep, clockwise: false)
            ctx.strokePath()
        }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(AmanRingGeometry.dropPath(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        ctx.fillPath()

        return ctx.makeImage()
    }

    static func image(state: State) -> NSImage? {
        guard let cg = cgImage(state: state) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: canvas, height: canvas))
    }

    static func pngData(state: State) -> Data? {
        guard let cg = cgImage(state: state) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
