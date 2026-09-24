import SwiftUI
import AppKit
import BenchmarkCore
import DiskHealthCore

/// Ce que la grille doit afficher : un résultat terminé, ou le test en cours.
struct BenchGridContent {
    var tests: [TestResult]
    var profile: BenchProfile
    /// Test en cours (nil si le résultat est terminé).
    var liveState: BenchmarkState?

    func result(_ spec: BenchTestSpec, _ direction: BenchDirection) -> TestResult? {
        tests.first { $0.spec.id == spec.id && $0.direction == direction }
    }
}

/// Couleurs des barres : bleu pour la lecture, orange pour l'écriture.
/// Paire vérifiée (daltonisme, contraste) en clair et en sombre.
enum BenchColors {
    static let read = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x00 / 255, green: 0x7A / 255, blue: 0xFF / 255, alpha: 1)
    })
    static let write = Color(nsColor: NSColor(srgbRed: 0xE0 / 255, green: 0x70 / 255, blue: 0x00 / 255, alpha: 1))

    static func color(for direction: BenchDirection) -> Color {
        direction == .read ? read : write
    }
}

/// Échelle des barres : chaque test est comparé à un SSD NVMe rapide récent (valeurs en Mo/s).
/// Le rapport est le même en Mo/s et en IOPS : la barre ne change pas avec l'unité.
enum BenchScale {
    static func referenceMegabytesPerSecond(for spec: BenchTestSpec, direction: BenchDirection) -> Double {
        switch spec.id {
        case "SEQ1M_QD8": return 7_000
        case "SEQ1M_QD1": return 5_000
        case "RND4K_QD64": return 2_500
        // En 4K QD1, les écritures passent par le cache du disque : bien plus rapides que les lectures.
        case "RND4K_QD1": return direction == .read ? 100 : 300
        default: return spec.pattern == .sequential ? 7_000 : 2_500
        }
    }

    static func fraction(megabytesPerSecond: Double, spec: BenchTestSpec, direction: BenchDirection) -> Double {
        min(1, max(0, megabytesPerSecond / referenceMegabytesPerSecond(for: spec, direction: direction)))
    }
}

struct BenchGridView: View {
    let content: BenchGridContent
    let unit: BenchUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                    header(.read)
                    header(.write)
                }
                ForEach(BenchTestSpec.defaultGrid, id: \.id) { spec in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.label)
                                .font(.body.weight(.semibold))
                            Text(caption(for: spec))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 150, alignment: .leading)
                        .help(spec.queueDepth > 1 ? Strings.benchHelpQD : "")

                        BenchGridCell(spec: spec, direction: .read, content: content, unit: unit)
                        BenchGridCell(spec: spec, direction: .write, content: content, unit: unit)
                    }
                }
            }
            Text(L("Bars compare each result with a fast recent NVMe SSD (about 7,000 MB/s for large files). A full bar means top-tier speed.",
                   "Les barres comparent chaque résultat à un SSD NVMe rapide récent (environ 7 000 Mo/s pour les gros fichiers). Une barre pleine correspond aux meilleurs disques."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func header(_ direction: BenchDirection) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(BenchColors.color(for: direction))
                .frame(width: 8, height: 8)
            Text(direction == .read ? L("Read", "Lecture") : L("Write", "Écriture"))
                .font(.headline)
            Text(unit == .mbps ? Formatters.speedUnit : "IOPS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(unit == .mbps ? L("Megabytes per second: how much data the drive moves each second. Higher is faster.",
                                "Mégaoctets par seconde : quantité de données transférée chaque seconde. Plus c'est haut, plus c'est rapide.")
                            : L("Input/output operations per second: how many separate requests the drive handles each second. Higher is faster.",
                                "Opérations d'entrée-sortie par seconde : nombre de requêtes traitées chaque seconde. Plus c'est haut, plus c'est rapide."))
    }

    private func caption(for spec: BenchTestSpec) -> String {
        let kind = spec.pattern == .sequential ? L("Large files", "Gros fichiers") : L("Small files", "Petits fichiers")
        let parallel = spec.queueDepth > 1
            ? L("\(spec.queueDepth) at once", "\(spec.queueDepth) en parallèle")
            : L("one at a time", "un à la fois")
        return "\(kind) · \(parallel)"
    }
}

struct BenchGridCell: View {
    let spec: BenchTestSpec
    let direction: BenchDirection
    let content: BenchGridContent
    let unit: BenchUnit

    private enum Phase {
        case notTested, done(TestResult), running(progress: Double, speed: Double?, pass: Int, total: Int), waiting, empty
    }

    private var phase: Phase {
        if direction == .write && !content.profile.includesWrites { return .notTested }
        if let result = content.result(spec, direction) { return .done(result) }
        guard let state = content.liveState else { return .empty }
        if case .pass(let specId, let dir, let pass, let total, let progress, let speed) = state,
           specId == spec.id, dir == direction {
            return .running(progress: progress, speed: speed, pass: pass, total: total)
        }
        return .waiting
    }

    private var unitText: String { unit == .mbps ? Formatters.speedUnit : "IOPS" }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            switch phase {
            case .running(let progress, let speed, let pass, let total):
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                cellBody(
                    value: speed.map(liveValue) ?? "…",
                    fraction: speed.map { BenchScale.fraction(megabytesPerSecond: $0, spec: spec, direction: direction) },
                    footnote: L("Pass \(pass) of \(total)", "Passe \(pass) sur \(total)"),
                    isLive: true
                )
            case .done(let result):
                cellBody(value: value(result), fraction: fraction(result), footnote: nil, isLive: false)
                    .help(detail(result))
            case .notTested:
                placeholder(L("Not tested", "Non testé"), style: .secondary)
            case .waiting:
                placeholder(L("Waiting", "En attente"), style: .tertiary)
            case .empty:
                placeholder("—", style: .tertiary)
            }
        }
        .frame(minWidth: 170, maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.18)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spec.label), \(direction == .read ? L("read", "lecture") : L("write", "écriture"))")
        .accessibilityValue(accessibilityValue)
    }

    /// Valeur + unité, puis la jauge colorée.
    private func cellBody(value: String, fraction: Double?, footnote: String?, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(isLive ? .secondary : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unitText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            SpeedBar(fraction: fraction ?? 0, color: BenchColors.color(for: direction))
                .opacity(fraction == nil ? 0.4 : (isLive ? 0.7 : 1))
        }
        .padding(.horizontal, 14)
    }

    private func placeholder(_ text: String, style: HierarchicalShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(text == "—" ? .title2 : .body)
                .foregroundStyle(style)
                .frame(maxWidth: .infinity, alignment: .trailing)
            SpeedBar(fraction: 0, color: .clear)
        }
        .padding(.horizontal, 14)
    }

    private func bestMegabytesPerSecond(_ result: TestResult) -> Double? {
        guard let best = BenchMath.best(result.passes) else { return nil }
        return BenchMath.megabytesPerSecond(bytes: best.bytes, seconds: best.seconds)
    }

    private func fraction(_ result: TestResult) -> Double? {
        bestMegabytesPerSecond(result).map { BenchScale.fraction(megabytesPerSecond: $0, spec: spec, direction: direction) }
    }

    private func value(_ result: TestResult) -> String {
        guard let best = BenchMath.best(result.passes) else { return "—" }
        switch unit {
        case .mbps: return Formatters.decimal(BenchMath.megabytesPerSecond(bytes: best.bytes, seconds: best.seconds))
        case .iops: return Formatters.integer(UInt64(BenchMath.iops(ios: best.ios, seconds: best.seconds).rounded()))
        }
    }

    private func liveValue(_ megabytesPerSecond: Double) -> String {
        switch unit {
        case .mbps: return Formatters.decimal(megabytesPerSecond)
        case .iops: return Formatters.integer(UInt64((megabytesPerSecond * 1_000_000 / Double(spec.blockSize)).rounded()))
        }
    }

    private func detail(_ result: TestResult) -> String {
        var parts = [L("Best of \(result.passes.count) passes.", "Meilleure passe sur \(result.passes.count).")]
        if let median = BenchMath.median(result.passes) {
            parts.append(L("Median: \(Formatters.speed(median)).", "Médiane : \(Formatters.speed(median))."))
        }
        if let p50 = result.latencyP50Micros, let p99 = result.latencyP99Micros {
            parts.append(L("Latency: \(Formatters.integer(UInt64(p50))) µs (median), \(Formatters.integer(UInt64(p99))) µs (99th percentile).",
                           "Latence : \(Formatters.integer(UInt64(p50))) µs (médiane), \(Formatters.integer(UInt64(p99))) µs (99 %)."))
        }
        return parts.joined(separator: " ")
    }

    private var accessibilityValue: String {
        switch phase {
        case .notTested: return L("Not tested", "Non testé")
        case .done(let r): return "\(value(r)) \(unit == .mbps ? L("megabytes per second", "mégaoctets par seconde") : "IOPS")"
        case .running(_, _, let pass, let total): return L("Test running, pass \(pass) of \(total)", "Test en cours, passe \(pass) sur \(total)")
        case .waiting: return L("Waiting", "En attente")
        case .empty: return L("No result", "Pas de résultat")
        }
    }
}

/// Jauge horizontale : piste discrète, remplissage coloré arrondi.
private struct SpeedBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                if fraction > 0 {
                    Capsule()
                        .fill(color)
                        // Une valeur non nulle reste visible, même très faible.
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
