import Foundation

public enum BenchPattern: String, Codable { case sequential, random }
public enum BenchDirection: String, Codable { case read, write }

public struct BenchTestSpec: Codable, Equatable {
    public let id: String
    public let label: String
    public let pattern: BenchPattern
    public let blockSize: Int
    public let queueDepth: Int
    public let recordsLatency: Bool

    public static let defaultGrid: [BenchTestSpec] = [
        BenchTestSpec(id: "SEQ1M_QD8", label: "SEQ 1M QD8", pattern: .sequential, blockSize: 1_048_576, queueDepth: 8, recordsLatency: false),
        BenchTestSpec(id: "SEQ1M_QD1", label: "SEQ 1M QD1", pattern: .sequential, blockSize: 1_048_576, queueDepth: 1, recordsLatency: false),
        BenchTestSpec(id: "RND4K_QD64", label: "RND 4K QD64", pattern: .random, blockSize: 4_096, queueDepth: 64, recordsLatency: false),
        BenchTestSpec(id: "RND4K_QD1", label: "RND 4K QD1", pattern: .random, blockSize: 4_096, queueDepth: 1, recordsLatency: true)
    ]
}

public enum BenchProfile: String, Codable, CaseIterable {
    case quick, standard, readOnly
    
    public var label: String {
        switch self {
        case .quick: return "Rapide"
        case .standard: return "Standard"
        case .readOnly: return "Lecture seule"
        }
    }
    
    public var passes: Int {
        switch self {
        case .quick: return 3
        case .standard: return 5
        case .readOnly: return 5
        }
    }
    
    public var timedPassSeconds: Double {
        switch self {
        case .quick: return 2.0
        case .standard: return 5.0
        case .readOnly: return 5.0
        }
    }
    
    public var pauseSeconds: Double {
        switch self {
        case .quick: return 1.0
        case .standard: return 3.0
        case .readOnly: return 3.0
        }
    }
    
    public var includesWrites: Bool {
        switch self {
        case .quick, .standard: return true
        case .readOnly: return false
        }
    }
}

public struct PassResult: Codable, Equatable {
    public let bytes: UInt64
    public let ios: UInt64
    public let seconds: Double
    
    public init(bytes: UInt64, ios: UInt64, seconds: Double) {
        self.bytes = bytes
        self.ios = ios
        self.seconds = seconds
    }
}

public struct TestResult: Codable, Equatable {
    public let spec: BenchTestSpec
    public let direction: BenchDirection
    public let passes: [PassResult]
    public let latencyP50Micros: Double?
    public let latencyP99Micros: Double?
    public let latencyP999Micros: Double?
    
    public init(spec: BenchTestSpec, direction: BenchDirection, passes: [PassResult], latencyP50Micros: Double?, latencyP99Micros: Double?, latencyP999Micros: Double?) {
        self.spec = spec
        self.direction = direction
        self.passes = passes
        self.latencyP50Micros = latencyP50Micros
        self.latencyP99Micros = latencyP99Micros
        self.latencyP999Micros = latencyP999Micros
    }
}

public struct BenchConditions: Codable, Equatable {
    public let volumeName: String
    public let fileSystem: String
    public let encrypted: Bool?
    public let onBattery: Bool?
    public let lowPowerMode: Bool?
    public let thermalStateStart: String
    public let temperatureStartC: Int?
    public let temperatureMaxC: Int?
    public let bytesWritten: UInt64
    
    public init(volumeName: String, fileSystem: String, encrypted: Bool?, onBattery: Bool?, lowPowerMode: Bool?, thermalStateStart: String, temperatureStartC: Int?, temperatureMaxC: Int?, bytesWritten: UInt64) {
        self.volumeName = volumeName
        self.fileSystem = fileSystem
        self.encrypted = encrypted
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermalStateStart = thermalStateStart
        self.temperatureStartC = temperatureStartC
        self.temperatureMaxC = temperatureMaxC
        self.bytesWritten = bytesWritten
    }
}

public struct BenchmarkResult: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let appVersion: String
    public let diskKey: String
    public let profile: BenchProfile
    public let fileSize: UInt64
    public let conditions: BenchConditions
    public let tests: [TestResult]
    public let completed: Bool
    public let stopReason: String?
    
    public init(id: UUID, date: Date, appVersion: String, diskKey: String, profile: BenchProfile, fileSize: UInt64, conditions: BenchConditions, tests: [TestResult], completed: Bool, stopReason: String?) {
        self.id = id
        self.date = date
        self.appVersion = appVersion
        self.diskKey = diskKey
        self.profile = profile
        self.fileSize = fileSize
        self.conditions = conditions
        self.tests = tests
        self.completed = completed
        self.stopReason = stopReason
    }
}
