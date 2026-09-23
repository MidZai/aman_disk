import Foundation
import BenchmarkCore

public class BenchmarkHistoryManager {
    public static let shared = BenchmarkHistoryManager()
    
    private let queue = DispatchQueue(label: "io.github.aman-disk.BenchmarkHistory")
    private let directoryUrl: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? AppInfo.bundleIdentifier
        directoryUrl = appSupport.appendingPathComponent(bundleId).appendingPathComponent("benchmarks")
        try? FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
    }
    
    public func saveResult(_ result: BenchmarkResult, forDiskKey diskKey: String) {
        queue.async {
            var results = self.loadResultsSync(forDiskKey: diskKey)
            results.insert(result, at: 0)
            if results.count > 50 {
                results = Array(results.prefix(50))
            }
            self.saveResultsSync(results, forDiskKey: diskKey)
        }
    }
    
    public func loadResults(forDiskKey diskKey: String, completion: @escaping ([BenchmarkResult]) -> Void) {
        queue.async {
            let res = self.loadResultsSync(forDiskKey: diskKey)
            DispatchQueue.main.async {
                completion(res)
            }
        }
    }
    
    public func loadResultsSync(forDiskKey diskKey: String) -> [BenchmarkResult] {
        let fileUrl = directoryUrl.appendingPathComponent("\(diskKey).json")
        guard let data = try? Data(contentsOf: fileUrl) else { return [] }
        guard let results = try? JSONDecoder().decode([BenchmarkResult].self, from: data) else { return [] }
        return results
    }
    
    private func saveResultsSync(_ results: [BenchmarkResult], forDiskKey diskKey: String) {
        let fileUrl = directoryUrl.appendingPathComponent("\(diskKey).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(results) {
            try? data.write(to: fileUrl)
        }
    }
}
