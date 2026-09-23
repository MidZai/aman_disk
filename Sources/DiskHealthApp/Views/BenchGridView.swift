import SwiftUI
import BenchmarkCore
import DiskHealthCore

struct BenchGridView: View {
    let currentState: BenchmarkState?
    let result: BenchmarkResult?
    let unit: BenchUnit
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 150)
                Text("Lecture").frame(maxWidth: .infinity).font(.headline)
                Text("Écriture").frame(maxWidth: .infinity).font(.headline)
            }
            .padding(.bottom, 8)
            
            ForEach(BenchTestSpec.defaultGrid, id: \.id) { spec in
                HStack(spacing: 0) {
                    HStack {
                        Text(spec.label)
                            .font(.body)
                        Spacer()
                        Image(systemName: "info.circle")
                            .help(spec.id.contains("QD") ? Strings.benchHelpQD : "")
                    }
                    .frame(width: 150)
                    .padding(.trailing, 8)
                    
                    BenchGridCell(spec: spec, direction: .read, profile: result?.profile ?? .standard, state: currentState, result: result, unit: unit)
                        .frame(maxWidth: .infinity)
                    
                    BenchGridCell(spec: spec, direction: .write, profile: result?.profile ?? .standard, state: currentState, result: result, unit: unit)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct BenchGridCell: View {
    let spec: BenchTestSpec
    let direction: BenchDirection
    let profile: BenchProfile
    let state: BenchmarkState?
    let result: BenchmarkResult?
    let unit: BenchUnit
    
    var body: some View {
        ZStack(alignment: .trailing) {
            Color(NSColor.controlBackgroundColor)
            
            if direction == .write && profile == .readOnly {
                Text("Non testé")
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            } else if let res = result, let testRes = res.tests.first(where: { $0.spec == spec && $0.direction == direction }) {
                // Done
                let best = BenchMath.best(testRes.passes)
                let val = valueStr(best: best)
                Text(val)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.trailing, 16)
            } else if case .pass(let tId, let pass, _, let prog, let spd) = state,
                      tId == testId(for: spec), direction == ((result?.tests.count ?? 0) < 4 ? BenchDirection.read : BenchDirection.write) {
                // Running
                GeometryReader { geo in
                    Color.accentColor.opacity(0.15)
                        .frame(width: geo.size.width * CGFloat(prog))
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(valueStrSpd(spd))
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("Passe \\(pass)")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.trailing, 16)
            } else if case .paused(_) = state, isNext(spec: spec, dir: direction) {
                Text("En attente")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            } else {
                Text("—")
                    .font(.title)
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .padding(.trailing, 16)
            }
        }
        .frame(height: 60)
        .border(Color(NSColor.separatorColor), width: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spec.label), \(direction == .read ? "lecture" : "écriture")")
        .accessibilityValue(accessibilityValueStr)
    }
    
    private var accessibilityValueStr: String {
        if direction == .write && profile == .readOnly {
            return "Non testé"
        } else if let res = result, let testRes = res.tests.first(where: { $0.spec == spec && $0.direction == direction }) {
            let best = BenchMath.best(testRes.passes)
            if unit == .mbps {
                let mbps = BenchMath.megabytesPerSecond(bytes: best?.bytes ?? 0, seconds: best?.seconds ?? 1)
                let formatted = Formatters.integer(UInt64(mbps))
                return "\(formatted) mégaoctets par seconde"
            } else {
                let iops = BenchMath.iops(ios: best?.ios ?? 0, seconds: best?.seconds ?? 1)
                let formatted = Formatters.integer(UInt64(iops))
                return "\(formatted) IOPS"
            }
        } else if case .pass(_, let pass, _, _, _) = state {
            return "Test en cours, passe \(pass)"
        } else if case .paused(_) = state, isNext(spec: spec, dir: direction) {
            return "En attente"
        }
        return "Vide"
    }
    
    private func valueStr(best: PassResult?) -> String {
        guard let b = best else { return "0" }
        if unit == .mbps {
            let mbps = BenchMath.megabytesPerSecond(bytes: b.bytes, seconds: b.seconds)
            return String(format: "%.1f", mbps)
        } else {
            let iops = BenchMath.iops(ios: b.ios, seconds: b.seconds)
            return "\\(Int(iops))"
        }
    }
    
    private func valueStrSpd(_ spdMBps: Double?) -> String {
        guard let s = spdMBps else { return "0.0" }
        if unit == .mbps {
            return String(format: "%.1f", s)
        } else {
            // Approximation: IOPS = MBps * 1048576 / blockSize
            let iops = (s * 1048576.0) / Double(spec.blockSize)
            return "\\(Int(iops))"
        }
    }
    
    private func testId(for spec: BenchTestSpec) -> String {
        return spec.label
    }
    
    private func isNext(spec: BenchTestSpec, dir: BenchDirection) -> Bool {
        return false // Optional
    }
}
