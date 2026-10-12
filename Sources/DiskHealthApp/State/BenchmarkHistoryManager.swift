import Foundation
import DiskHealthCore
import BenchmarkCore

/// Performance test results, one JSON file per drive (50 results at most).
final class BenchmarkHistoryManager: @unchecked Sendable {
    static let shared = BenchmarkHistoryManager()
    static let maxResults = 50

    private let queue = DispatchQueue(label: "io.github.aman-disk.benchmark-history", qos: .utility)
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = appSupport.appendingPathComponent(AppInfo.bundleIdentifier).appendingPathComponent("benchmarks")
        }
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    /// Saves a result under `result.diskKey`.
    func save(_ result: BenchmarkResult) {
        queue.async {
            var results = self.read(key: result.diskKey)
            results.insert(result, at: 0)
            self.write(Array(results.prefix(Self.maxResults)), key: result.diskKey)
        }
    }

    /// A drive's results, newest first, under its stable key (model + serial number) only.
    /// Files from 0.9 named after the model alone or the BSD name (`disk0`) could belong to
    /// another drive, so they are no longer read.
    func results(for disk: RealDisk) -> [BenchmarkResult] {
        queue.sync { self.readAll(keys: Self.keys(for: disk)) }
    }

    func loadResults(for disk: RealDisk) async -> [BenchmarkResult] {
        let keys = Self.keys(for: disk)
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.readAll(keys: keys)) }
        }
    }

    private static func keys(for disk: RealDisk) -> [String] {
        [disk.benchmarkKey]
    }

    private func readAll(keys: [String]) -> [BenchmarkResult] {
        var seen = Set<UUID>()
        return keys.flatMap { read(key: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    private func fileURL(key: String) -> URL {
        directoryURL.appendingPathComponent("\(key).json")
    }

    private func read(key: String) -> [BenchmarkResult] {
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return [] }
        return (try? JSONDecoder().decode([BenchmarkResult].self, from: data)) ?? []
    }

    private func write(_ results: [BenchmarkResult], key: String) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: fileURL(key: key), options: .atomic)
    }
}
