import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7j"
    
    public var id: String { rawValue }
    
    public var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        }
    }
}

public struct AggregatedPoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let temperature: Double
    public let segment: Int
}

public struct AggregationResult {
    public let points: [AggregatedPoint]
    public let min: Int?
    public let max: Int?
    public let average: Int?
}

public enum HistoryAggregation {
    public static func aggregate(samples: [HistorySample], range: HistoryRange) -> AggregationResult {
        if samples.isEmpty {
            return AggregationResult(points: [], min: nil, max: nil, average: nil)
        }
        
        let temps = samples.compactMap { $0.temperatureC }
        let minTemp = temps.min()
        let maxTemp = temps.max()
        let avgTemp = temps.isEmpty ? nil : Int(round(Double(temps.reduce(0, +)) / Double(temps.count)))
        
        var points: [AggregatedPoint] = []
        
        switch range {
        case .oneHour:
            // Samples bruts
            // Break if > 15 mins (3 * 5 mins default interval)
            let threshold: TimeInterval = 15 * 60
            var currentSegment = 0
            for i in 0..<samples.count {
                let sample = samples[i]
                guard let temp = sample.temperatureC else { continue }
                
                if i > 0 {
                    let prev = samples[i-1]
                    if sample.date.timeIntervalSince(prev.date) > threshold {
                        currentSegment += 1
                    }
                }
                points.append(AggregatedPoint(date: sample.date, temperature: Double(temp), segment: currentSegment))
            }
            
        case .twentyFourHours:
            points = groupAndAverage(samples: samples, chunkSize: 15 * 60)
            
        case .sevenDays:
            points = groupAndAverage(samples: samples, chunkSize: 60 * 60)
        }
        
        return AggregationResult(points: points, min: minTemp, max: maxTemp, average: avgTemp)
    }
    
    private static func groupAndAverage(samples: [HistorySample], chunkSize: TimeInterval) -> [AggregatedPoint] {
        guard let first = samples.first else { return [] }
        
        var points: [AggregatedPoint] = []
        var currentChunkStart = first.date
        var chunkTemps: [Double] = []
        var currentSegment = 0
        var lastChunkStart: Date? = nil
        
        for sample in samples {
            guard let temp = sample.temperatureC else { continue }
            
            if sample.date.timeIntervalSince(currentChunkStart) >= chunkSize {
                // close chunk
                if !chunkTemps.isEmpty {
                    let avg = chunkTemps.reduce(0, +) / Double(chunkTemps.count)
                    if let lastStart = lastChunkStart {
                        if currentChunkStart.timeIntervalSince(lastStart) > (3 * chunkSize) {
                            currentSegment += 1
                        }
                    }
                    points.append(AggregatedPoint(date: currentChunkStart, temperature: avg, segment: currentSegment))
                    lastChunkStart = currentChunkStart
                }
                
                // Advance chunk start to the correct block for current sample
                let intervals = floor(sample.date.timeIntervalSince(currentChunkStart) / chunkSize)
                currentChunkStart = currentChunkStart.addingTimeInterval(intervals * chunkSize)
                chunkTemps = [Double(temp)]
            } else {
                chunkTemps.append(Double(temp))
            }
        }
        
        if !chunkTemps.isEmpty {
            let avg = chunkTemps.reduce(0, +) / Double(chunkTemps.count)
            if let lastStart = lastChunkStart {
                if currentChunkStart.timeIntervalSince(lastStart) > (3 * chunkSize) {
                    currentSegment += 1
                }
            }
            points.append(AggregatedPoint(date: currentChunkStart, temperature: avg, segment: currentSegment))
        }
        
        return points
    }
}
