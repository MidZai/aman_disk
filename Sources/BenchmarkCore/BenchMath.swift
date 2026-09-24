import Foundation

public enum FreeSpaceVerdict: Equatable {
    case ok
    case tooLargeForFreeSpace
    case wouldLeaveTooLittle
}

public enum BenchMath {
    public static func megabytesPerSecond(bytes: UInt64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) / seconds / 1_000_000.0
    }
    
    public static func iops(ios: UInt64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(ios) / seconds
    }
    
    public static func best(_ passes: [PassResult]) -> PassResult? {
        passes.max(by: {
            megabytesPerSecond(bytes: $0.bytes, seconds: $0.seconds) < megabytesPerSecond(bytes: $1.bytes, seconds: $1.seconds)
        })
    }
    
    public static func median(_ passes: [PassResult]) -> Double? {
        guard !passes.isEmpty else { return nil }
        let speeds = passes.map { megabytesPerSecond(bytes: $0.bytes, seconds: $0.seconds) }.sorted()
        let count = speeds.count
        if count % 2 == 0 {
            return (speeds[count / 2 - 1] + speeds[count / 2]) / 2.0
        } else {
            return speeds[count / 2]
        }
    }
    
    public static func percentile(_ sortedNanos: [UInt64], _ p: Double) -> Double? {
        guard !sortedNanos.isEmpty else { return nil }
        let n = Double(sortedNanos.count)
        let rank = ceil((p / 100.0) * n)
        let index = max(0, min(sortedNanos.count - 1, Int(rank) - 1))
        return Double(sortedNanos[index]) / 1000.0
    }
    
    /// Maximum amount written by a test: the test file, then at most its size once per write
    /// pass (sequential passes stop at the end of the file, random passes at
    /// `max_bytes` = file size).
    public static func maxBytesWritten(fileSize: UInt64, profile: BenchProfile, testsPerDirection: Int = BenchTestSpec.defaultGrid.count) -> UInt64 {
        if !profile.includesWrites {
            return fileSize
        }
        return fileSize.saturatingMultiplied(by: UInt64(1 + testsPerDirection * profile.passes))
    }

    /// Estimated maximum duration of a test, in seconds: file creation (400 MB/s, a safe figure
    /// for a SATA SSD), passes capped at `timedPassSeconds`, pauses between tests.
    public static func estimatedMaxDuration(fileSize: UInt64, profile: BenchProfile, testsPerDirection: Int = BenchTestSpec.defaultGrid.count) -> TimeInterval {
        let tests = testsPerDirection * (profile.includesWrites ? 2 : 1)
        let prepare = Double(fileSize) / 400_000_000
        let passes = Double(tests * profile.passes) * (profile.timedPassSeconds + 0.2)
        let pauses = Double(max(0, tests - 1)) * profile.pauseSeconds
        return prepare + passes + pauses
    }
    
    public static func checkFreeSpace(fileSize: UInt64, available: UInt64) -> FreeSpaceVerdict {
        if fileSize > UInt64(Double(available) * 0.2) {
            return .tooLargeForFreeSpace
        }
        if available < fileSize + 5_368_709_120 { // 5 GiB = 5 * 1024^3 = 5,368,709,120 bytes
            return .wouldLeaveTooLittle
        }
        return .ok
    }
}
