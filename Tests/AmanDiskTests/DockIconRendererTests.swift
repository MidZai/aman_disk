import AppKit
import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Dock icon rendering, compared with the brand kit PNGs.
@Suite struct DockIconRendererTests {
    static let kitDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Branding/Aman-Disk-brand/health-states/app-icon-png-1024")
    
    /// 8-bit RGBA pixels, 1024 × 1024, sRGB.
    static func pixels(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let ctx = CGContext(data: &buffer, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return buffer
    }
    
    /// Share of pixels where one channel differs by more than 24/255.
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
        // Renderings are written out for visual comparison if AMAN_RENDER_DIR is set.
        if let dir = ProcessInfo.processInfo.environment["AMAN_RENDER_DIR"], let png = DockIconRenderer.pngData(state: state) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("dock-\(kitFile)"))
        }
        return Self.differingRatio(Self.pixels(rendered), Self.pixels(kit))
    }
    
    @Test func matchesKitAt80Percent() throws {
        let ratio = try compare(state: .init(percent: 80, level: .water), kitFile: "aman-080.png")
        #expect(ratio < 0.01, "different pixels: \(ratio)")
    }
    
    @Test func matchesKitAt45PercentOrange() throws {
        let ratio = try compare(state: .init(percent: 45, level: .orange), kitFile: "aman-045.png")
        #expect(ratio < 0.01, "different pixels: \(ratio)")
    }
    
    @Test func stateRules() {
        // Known percentage: proportional arc, most severe color.
        let s1 = DockIconRenderer.State(health: HealthAssessment(status: .caution, healthPercent: 90, reasons: []), capability: .supported)
        #expect(s1.percent == 90 && s1.level == .orange)
        // Unknown and good status: official icon.
        let s2 = DockIconRenderer.State(health: HealthAssessment(status: .good, healthPercent: nil, reasons: []), capability: .supported)
        #expect(s2.isOfficialIcon && s2.drawnPercent == 80)
        // Unknown but bad status: 80% gauge in red, never a made-up percentage.
        let s3 = DockIconRenderer.State(health: HealthAssessment(status: .bad, healthPercent: nil, reasons: []), capability: .supported)
        #expect(s3.percent == nil && s3.level == .red && !s3.isOfficialIcon)
    }
}
