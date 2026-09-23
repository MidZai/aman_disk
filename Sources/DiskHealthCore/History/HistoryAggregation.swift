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

public struct AggregatedPoint: Identifiable {
    public let id = UUID()
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

public struct AggregationResult {
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
            return AggregationResult(points: [], min: nil, max: nil, average: nil, measurementCount: 0, gaps: [])
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

    private static func groupAndAverage(samples: [HistorySample], chunkSize: TimeInterval) -> [AggregatedPoint] {
        guard let first = samples.first else { return [] }

        var points: [AggregatedPoint] = []
        var currentChunkStart = first.date
        var chunk: [HistorySample] = []
        var currentSegment = 0
        var lastChunkStart: Date? = nil

        func closeChunk() {
            guard !chunk.isEmpty else { return }
            var sum = 0.0
            var weight = 0
            var lo = Double.greatestFiniteMagnitude
            var hi = -Double.greatestFiniteMagnitude
            for s in chunk {
                let t = Double(s.temperatureC!)
                sum += t * Double(s.measurementCount)
                weight += s.measurementCount
                lo = Swift.min(lo, s.temperatureMinC.map(Double.init) ?? t)
                hi = Swift.max(hi, s.temperatureMaxC.map(Double.init) ?? t)
            }
            if let lastStart = lastChunkStart, currentChunkStart.timeIntervalSince(lastStart) > (3 * chunkSize) {
                currentSegment += 1
            }
            points.append(AggregatedPoint(date: currentChunkStart, temperature: sum / Double(weight), segment: currentSegment, minTemperature: lo, maxTemperature: hi))
            lastChunkStart = currentChunkStart
        }

        for sample in samples {
            if sample.date.timeIntervalSince(currentChunkStart) >= chunkSize {
                closeChunk()
                // Avance au bloc qui contient la mesure courante
                let intervals = floor(sample.date.timeIntervalSince(currentChunkStart) / chunkSize)
                currentChunkStart = currentChunkStart.addingTimeInterval(intervals * chunkSize)
                chunk = [sample]
            } else {
                chunk.append(sample)
            }
        }
        closeChunk()

        return points
    }
}
