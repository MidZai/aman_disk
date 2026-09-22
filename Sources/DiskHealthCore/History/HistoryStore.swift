import Foundation

public class HistoryStore {
    public static let shared = HistoryStore()
    
    private let queue = DispatchQueue(label: "com.diskhealth.history", qos: .background)
    private let historyFolderURL: URL
    
    public init(baseURL: URL? = nil) {
        if let base = baseURL {
            historyFolderURL = base.appendingPathComponent("History")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            historyFolderURL = appSupport.appendingPathComponent("DiskHealth").appendingPathComponent("History")
        }
        
        try? FileManager.default.createDirectory(at: historyFolderURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func fileURL(for key: String) -> URL {
        return historyFolderURL.appendingPathComponent("\(key).json")
    }
    
    private func loadRaw(key: String) -> [HistorySample] {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([HistorySample].self, from: data)) ?? []
    }
    
    private func saveRaw(key: String, samples: [HistorySample]) {
        let url = fileURL(for: key)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(samples) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    public func append(_ sample: HistorySample, for key: String) {
        queue.async {
            var samples = self.loadRaw(key: key)
            
            if let last = samples.last {
                let timeDiff = sample.date.timeIntervalSince(last.date)
                if timeDiff > 0 && timeDiff < (4 * 60) {
                    let tempDiff = abs((sample.temperatureC ?? 0) - (last.temperatureC ?? 0))
                    if tempDiff < 3 {
                        // Skip adding if < 4 mins and temp changed by < 3 degrees
                        return
                    }
                }
            }
            
            samples.append(sample)
            
            // Supprimer les echantillons de plus de 90 jours
            let ninetyDaysAgo = Date().addingTimeInterval(-90 * 24 * 3600)
            samples = samples.filter { $0.date >= ninetyDaysAgo }
            
            self.saveRaw(key: key, samples: samples)
        }
    }
    
    public func samples(for key: String, since: Date) -> [HistorySample] {
        return queue.sync {
            let all = loadRaw(key: key)
            return all.filter { $0.date >= since }
        }
    }
    
    public func folderPath() -> String {
        return historyFolderURL.path
    }
}
