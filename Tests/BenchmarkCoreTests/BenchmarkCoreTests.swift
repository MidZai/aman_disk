import Testing
import Foundation
@testable import BenchmarkCore

@Suite final class BenchmarkCoreTests {
    
    @Test func testMegabytesPerSecond() {
        let mbps = BenchMath.megabytesPerSecond(bytes: 1_073_741_824, seconds: 0.5)
        #expect(abs((mbps) - (2147.48)) <= 0.01)
    }
    
    @Test func testIOPS() {
        let iops = BenchMath.iops(ios: 10_000, seconds: 2.0)
        #expect(abs((iops) - (5000.0)) <= 0.01)
    }
    
    @Test func testPercentile() {
        let array = (1...100).map { UInt64($0 * 1000) } // 1 to 100 microseconds (in nanos)
        #expect(abs((BenchMath.percentile(array, 50.0)!) - (50.0)) <= 0.1)
        #expect(abs((BenchMath.percentile(array, 99.0)!) - (99.0)) <= 0.1)
        #expect(abs((BenchMath.percentile(array, 99.9)!) - (100.0)) <= 0.1)
        #expect(BenchMath.percentile([], 50.0) == nil)
    }
    
    @Test func testMedianAndBest() {
        let passes4 = [
            PassResult(bytes: 10_000_000, ios: 10, seconds: 1.0), // 10 MB/s
            PassResult(bytes: 40_000_000, ios: 40, seconds: 1.0), // 40 MB/s
            PassResult(bytes: 20_000_000, ios: 20, seconds: 1.0), // 20 MB/s
            PassResult(bytes: 30_000_000, ios: 30, seconds: 1.0)  // 30 MB/s
        ]
        
        let median4 = BenchMath.median(passes4)
        #expect(abs((median4!) - (25.0)) <= 0.1)
        
        let passes5 = passes4 + [PassResult(bytes: 50_000_000, ios: 50, seconds: 1.0)] // 50 MB/s
        let median5 = BenchMath.median(passes5)
        #expect(abs((median5!) - (30.0)) <= 0.1)
        
        let best = BenchMath.best(passes5)
        #expect(best?.bytes == 50_000_000)
    }
    
    @Test func testMaxBytesWritten() {
        let gio = UInt64(1073741824)
        #expect(BenchMath.maxBytesWritten(fileSize: gio, profile: .standard) == 21 * gio)
        #expect(BenchMath.maxBytesWritten(fileSize: gio, profile: .quick) == 13 * gio)
        #expect(BenchMath.maxBytesWritten(fileSize: gio, profile: .readOnly) == gio)
    }
    
    @Test func testCheckFreeSpace() {
        let gio = UInt64(1073741824)
        #expect(BenchMath.checkFreeSpace(fileSize: gio, available: 100 * gio) == .ok)
        #expect(BenchMath.checkFreeSpace(fileSize: 4 * gio, available: 12 * gio) == .tooLargeForFreeSpace)
        #expect(BenchMath.checkFreeSpace(fileSize: gio, available: UInt64(5.5 * Double(gio))) == .wouldLeaveTooLittle)
    }
    
    @Test func testCodableBenchmarkResult() throws {
        let result = BenchmarkResult(
            id: UUID(),
            date: Date(),
            appVersion: "1.0",
            diskKey: "TEST_DISK",
            profile: .standard,
            fileSize: 1024,
            conditions: BenchConditions(
                volumeName: "Macintosh HD",
                fileSystem: "APFS",
                encrypted: true,
                onBattery: false,
                lowPowerMode: false,
                thermalStateStart: "nominal",
                temperatureStartC: 40,
                temperatureMaxC: 45,
                bytesWritten: 10240
            ),
            tests: [
                TestResult(
                    spec: BenchTestSpec.defaultGrid[0],
                    direction: .read,
                    passes: [PassResult(bytes: 1024, ios: 1, seconds: 1.0)],
                    latencyP50Micros: nil,
                    latencyP99Micros: nil,
                    latencyP999Micros: nil
                )
            ],
            completed: true,
            stopReason: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BenchmarkResult.self, from: data)
        
        #expect(result == decoded)
    }
}
