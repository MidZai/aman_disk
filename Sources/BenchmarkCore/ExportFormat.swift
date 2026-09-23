import Foundation
import DiskHealthCore

public struct ExportFormat: Codable {
    public let schemaVersion: Int
    public let physical: PhysicalDisk
    public let smart: DiskHealthSnapshot?
    public let health: HealthAssessment
    public let lastRead: Date
    public let benchmark: BenchmarkResult?
    
    public init(schemaVersion: Int, physical: PhysicalDisk, smart: DiskHealthSnapshot?, health: HealthAssessment, lastRead: Date, benchmark: BenchmarkResult?) {
        self.schemaVersion = schemaVersion
        self.physical = physical
        self.smart = smart
        self.health = health
        self.lastRead = lastRead
        self.benchmark = benchmark
    }
}
