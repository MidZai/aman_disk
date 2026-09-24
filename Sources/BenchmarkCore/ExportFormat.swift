import Foundation
import DiskHealthCore

/// Point de l'historique de température exporté (moyenne horaire).
public struct ExportedTemperaturePoint: Codable, Equatable {
    public let date: Date
    public let averageC: Double
    public let minC: Double?
    public let maxC: Double?

    public init(date: Date, averageC: Double, minC: Double?, maxC: Double?) {
        self.date = date
        self.averageC = averageC
        self.minC = minC
        self.maxC = maxC
    }
}

/// Rapport JSON. Les champs ajoutés après la v2 sont optionnels : les anciens rapports se relisent.
public struct ExportFormat: Codable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let generator: String?
    public let physical: PhysicalDisk
    public let smart: DiskHealthSnapshot?
    public let health: HealthAssessment
    public let metrics: DiskMetrics?
    public let lastRead: Date
    public let benchmark: BenchmarkResult?
    public let temperatureHistory: [ExportedTemperaturePoint]?

    public init(schemaVersion: Int = ExportFormat.currentSchemaVersion, generator: String? = nil, physical: PhysicalDisk,
                smart: DiskHealthSnapshot?, health: HealthAssessment, metrics: DiskMetrics? = nil, lastRead: Date,
                benchmark: BenchmarkResult?, temperatureHistory: [ExportedTemperaturePoint]? = nil) {
        self.schemaVersion = schemaVersion
        self.generator = generator
        self.physical = physical
        self.smart = smart
        self.health = health
        self.metrics = metrics
        self.lastRead = lastRead
        self.benchmark = benchmark
        self.temperatureHistory = temperatureHistory
    }
}
