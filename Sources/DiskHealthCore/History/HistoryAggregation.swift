import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7j"
    case thirtyDays = "30j"

    public var id: String { rawValue }

    public var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .thirtyDays: return 30 * 24 * 3600
        }
    }

    /// Au-delà de 24 h, le graphique montre la moyenne et la plage min–max.
    public var showsMinMaxBand: Bool {
        self == .sevenDays || self == .thirtyDays
    }

    /// Taille des regroupements ; nil = mesures brutes.
    var chunkSize: TimeInterval? {
        switch self {
        case .oneHour: return nil
        case .twentyFourHours: return 5 * 60
        case .sevenDays: return 60 * 60
        case .thirtyDays: return 4 * 60 * 60
        }
    }
}

public struct AggregatedPoint: Identifiable, Equatable {
    /// Identifiant stable (la date) : Swift Charts peut comparer deux rendus au lieu de tout redessiner.
    public var id: Date { date }
    public let date: Date
    public let temperature: Double
    public let segment: Int
    public let minTemperature: Double?
    public let maxTemperature: Double?

    public init(date: Date, temperature: Double, segment: Int, minTemperature: Double? = nil, maxTemperature: Double? = nil) {
        self.date = date
        self.temperature = temperature
        self.segment = segment
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
    }
}

public struct AggregationResult: Equatable {
    public static let empty = AggregationResult(points: [], min: nil, max: nil, average: nil, measurementCount: 0, gaps: [])

    public let points: [AggregatedPoint]
    public let min: Int?
    public let max: Int?
    public let average: Int?
    /// Nombre de mesures réelles couvertes (les tranches compactées comptent pour leurs mesures).
    public let measurementCount: Int
    /// Périodes sans mesure (coupures) entre deux segments.
    public let gaps: [DateInterval]
}

public enum HistoryAggregation {
    /// Intervalle nominal de la surveillance continue.
    public static let nominalInterval: TimeInterval = 30

    public static func aggregate(samples: [HistorySample], range: HistoryRange) -> AggregationResult {
        let withTemp = samples.filter { $0.temperatureC != nil }
        if withTemp.isEmpty {
            return .empty
        }

        var minTemp: Int? = nil
        var maxTemp: Int? = nil
        var weightedSum = 0.0
        var count = 0
        for s in withTemp {
            let t = s.temperatureC!
            let lo = s.temperatureMinC ?? t
            let hi = s.temperatureMaxC ?? t
            minTemp = Swift.min(minTemp ?? lo, lo)
            maxTemp = Swift.max(maxTemp ?? hi, hi)
            weightedSum += Double(t) * Double(s.measurementCount)
            count += s.measurementCount
        }
        let avgTemp = count > 0 ? Int(round(weightedSum / Double(count))) : nil

        let points: [AggregatedPoint]
        if let chunk = range.chunkSize {
            points = groupAndAverage(samples: withTemp, chunkSize: chunk)
        } else {
            points = rawPoints(samples: withTemp)
        }

        return AggregationResult(points: points, min: minTemp, max: maxTemp, average: avgTemp, measurementCount: count, gaps: gaps(in: points))
    }

    /// Seuil de coupure : 3 × l'intervalle réel entre mesures (au moins 3 × 30 s).
    /// L'intervalle réel est la médiane des écarts, ce qui garde les anciens historiques
    /// (une mesure toutes les 5 min) lisibles sans les découper.
    public static func breakThreshold(for samples: [HistorySample]) -> TimeInterval {
        guard samples.count > 1 else { return 3 * nominalInterval }
        var diffs: [TimeInterval] = []
        diffs.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            diffs.append(samples[i].date.timeIntervalSince(samples[i - 1].date))
        }
        diffs.sort()
        let median = diffs[diffs.count / 2]
        return 3 * Swift.max(nominalInterval, median)
    }

    private static func rawPoints(samples: [HistorySample]) -> [AggregatedPoint] {
        let threshold = breakThreshold(for: samples)
        var points: [AggregatedPoint] = []
        var currentSegment = 0
        for i in 0..<samples.count {
            let sample = samples[i]
            if i > 0 && sample.date.timeIntervalSince(samples[i - 1].date) > threshold {
                currentSegment += 1
            }
            points.append(AggregatedPoint(
                date: sample.date,
                temperature: Double(sample.temperatureC!),
                segment: currentSegment,
                minTemperature: sample.temperatureMinC.map(Double.init),
                maxTemperature: sample.temperatureMaxC.map(Double.init)
            ))
        }
        return points
    }

    private static func gaps(in points: [AggregatedPoint]) -> [DateInterval] {
        guard points.count > 1 else { return [] }
        var result: [DateInterval] = []
        for i in 1..<points.count where points[i].segment != points[i - 1].segment {
            let start = points[i - 1].date
            let end = points[i].date
            if end > start { result.append(DateInterval(start: start, end: end)) }
        }
        return result
    }

    /// Regroupe les mesures en tranches alignées sur l'horloge (multiples de `chunkSize`) :
    /// les tranches ne bougent pas d'un rechargement à l'autre, donc la courbe ne « tremble » pas
    /// toutes les 30 s quand la fenêtre glisse.
    private static func groupAndAverage(samples: [HistorySample], chunkSize: TimeInterval) -> [AggregatedPoint] {
        var points: [AggregatedPoint] = []
        var chunk: [HistorySample] = []
        var chunkStart: TimeInterval = -1
        var currentSegment = 0
        var lastChunkStart: TimeInterval? = nil

        func closeChunk() {
            guard !chunk.isEmpty else { return }
            var sum = 0.0
            var weight = 0
            var lo = Double.greatestFiniteMagnitude
            var hi = -Double.greatestFiniteMagnitude
            for s in chunk {
                guard let temperature = s.temperatureC else { continue }
                let t = Double(temperature)
                sum += t * Double(s.measurementCount)
                weight += s.measurementCount
                lo = Swift.min(lo, s.temperatureMinC.map(Double.init) ?? t)
                hi = Swift.max(hi, s.temperatureMaxC.map(Double.init) ?? t)
            }
            guard weight > 0 else { return }
            if let lastStart = lastChunkStart, chunkStart - lastStart > 3 * chunkSize {
                currentSegment += 1
            }
            // Point placé au milieu de sa tranche.
            points.append(AggregatedPoint(date: Date(timeIntervalSince1970: chunkStart + chunkSize / 2), temperature: sum / Double(weight), segment: currentSegment, minTemperature: lo, maxTemperature: hi))
            lastChunkStart = chunkStart
        }

        for sample in samples {
            let start = floor(sample.date.timeIntervalSince1970 / chunkSize) * chunkSize
            if start != chunkStart {
                closeChunk()
                chunk = []
                chunkStart = start
            }
            chunk.append(sample)
        }
        closeChunk()

        return points
    }
}
