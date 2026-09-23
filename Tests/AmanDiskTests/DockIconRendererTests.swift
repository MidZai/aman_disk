import AppKit
import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Phase 5 (0.9) : rendu de l'icône du Dock comparé aux PNG du kit de marque.
@Suite struct DockIconRendererTests {
    static let kitDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Branding/Aman-Disk-brand/etats-sante/icone-app-png-1024")
    
    /// Pixels RGBA 8 bits, 1024 × 1024, sRGB.
    static func pixels(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let ctx = CGContext(data: &buffer, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return buffer
    }
    
    /// Part des pixels dont un canal diffère de plus de 24/255.
    static func differingRatio(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var differing = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            for c in 0..<4 where abs(Int(a[i + c]) - Int(b[i + c])) > 24 {
                differing += 1
                break
            }
        }
        return Double(differing) / Double(a.count / 4)
    }
    
    func compare(state: DockIconRenderer.State, kitFile: String) throws -> Double {
        let rendered = try #require(DockIconRenderer.cgImage(state: state))
        let kitURL = Self.kitDir.appendingPathComponent(kitFile)
        let kit = try #require(NSImage(contentsOf: kitURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        // Rendus écrits pour comparaison visuelle si AMAN_RENDER_DIR est défini.
        if let dir = ProcessInfo.processInfo.environment["AMAN_RENDER_DIR"], let png = DockIconRenderer.pngData(state: state) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("dock-\(kitFile)"))
        }
        return Self.differingRatio(Self.pixels(rendered), Self.pixels(kit))
    }
    
    @Test func matchesKitAt80Percent() throws {
        let ratio = try compare(state: .init(percent: 80, level: .water), kitFile: "aman-080.png")
        #expect(ratio < 0.01, "pixels différents : \(ratio)")
    }
    
    @Test func matchesKitAt45PercentOrange() throws {
        let ratio = try compare(state: .init(percent: 45, level: .orange), kitFile: "aman-045.png")
        #expect(ratio < 0.01, "pixels différents : \(ratio)")
    }
    
    @Test func stateRules() {
        // Pourcentage connu : arc proportionnel, couleur la plus grave.
        let s1 = DockIconRenderer.State(health: HealthAssessment(status: .caution, healthPercent: 90, reasons: []), capability: .supported)
        #expect(s1.percent == 90 && s1.level == .orange)
        // Inconnu et bon état : icône officielle.
        let s2 = DockIconRenderer.State(health: HealthAssessment(status: .good, healthPercent: nil, reasons: []), capability: .supported)
        #expect(s2.isOfficialIcon && s2.drawnPercent == 80)
        // Inconnu mais mauvais état : jauge 80 % en rouge, jamais de pourcentage inventé.
        let s3 = DockIconRenderer.State(health: HealthAssessment(status: .bad, healthPercent: nil, reasons: []), capability: .supported)
        #expect(s3.percent == nil && s3.level == .red && !s3.isOfficialIcon)
    }
}
