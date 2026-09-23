import Foundation

public class HistoryStore {
    public static let shared = HistoryStore()

    /// Dossier d'Application Support de l'app (identique à l'identifiant du bundle).
    public static let defaultFolderName = "io.github.aman-disk.AmanDisk"
    /// Pleine résolution conservée sur cette durée.
    public static let fullResolutionWindow: TimeInterval = 24 * 3600
    /// Taille des tranches de compactage au-delà de 24 h.
    public static let compactionBucket: TimeInterval = 5 * 60
    /// Au-delà, les mesures sont supprimées.
    public static let retention: TimeInterval = 30 * 24 * 3600
    /// Deux mesures plus rapprochées sont considérées comme un doublon.
    public static let minimumSpacing: TimeInterval = 15

    private let queue = DispatchQueue(label: "com.diskhealth.history", qos: .background)
    private let historyFolderURL: URL
    /// Cache mémoire : évite de relire le fichier à chaque mesure (toutes les 30 s).
    private var cache: [String: [HistorySample]] = [:]

    public init(baseURL: URL? = nil) {
        if let base = baseURL {
            historyFolderURL = base.appendingPathComponent("History")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            historyFolderURL = appSupport.appendingPathComponent(Self.defaultFolderName).appendingPathComponent("History")
        }

        try? FileManager.default.createDirectory(at: historyFolderURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func fileURL(for key: String) -> URL {
        return historyFolderURL.appendingPathComponent("\(key).json")
    }

    private func loadRaw(key: String) -> [HistorySample] {
        if let cached = cache[key] { return cached }
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let samples = (try? decoder.decode([HistorySample].self, from: data)) ?? []
        cache[key] = samples
        return samples
    }

    private func saveRaw(key: String, samples: [HistorySample]) {
        cache[key] = samples
        let url = fileURL(for: key)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(samples) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Ajout historique (v0.2) : rejette les mesures à moins de 4 min et 3 °C de la précédente.
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

            let cutoff = Date().addingTimeInterval(-Self.retention)
            samples = samples.filter { $0.date >= cutoff }

            self.saveRaw(key: key, samples: samples)
        }
    }

    /// Ajout en pleine résolution, utilisé par la surveillance continue (une mesure toutes les 30 s).
    /// Seuls les doublons (moins de 15 s d'écart) sont ignorés.
    public func record(_ sample: HistorySample, for key: String) {
        queue.async {
            var samples = self.loadRaw(key: key)
            if let last = samples.last, sample.date.timeIntervalSince(last.date) < Self.minimumSpacing {
                return
            }
            samples.append(sample)
            self.saveRaw(key: key, samples: samples)
        }
    }

    /// Compacte tous les historiques : pleine résolution sur 24 h, tranches de 5 min jusqu'à 30 jours.
    public func compactAll(now: Date = Date()) {
        queue.sync {
            let keys = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent } ?? []
            for key in Set(keys).union(cache.keys) {
                let samples = loadRaw(key: key)
                let compacted = Self.compact(samples, now: now)
                if compacted != samples {
                    saveRaw(key: key, samples: compacted)
                }
            }
        }
    }

    /// Règle de conservation, sans effet de bord (testable).
    public static func compact(_ samples: [HistorySample], now: Date) -> [HistorySample] {
        let retentionCutoff = now.addingTimeInterval(-retention)
        let fullResCutoff = now.addingTimeInterval(-fullResolutionWindow)

        let sorted = samples.filter { $0.date >= retentionCutoff }.sorted { $0.date < $1.date }
        let old = sorted.filter { $0.date < fullResCutoff }
        let recent = sorted.filter { $0.date >= fullResCutoff }

        var buckets: [TimeInterval: [HistorySample]] = [:]
        for sample in old {
            let start = floor(sample.date.timeIntervalSince1970 / compactionBucket) * compactionBucket
            buckets[start, default: []].append(sample)
        }

        let compacted: [HistorySample] = buckets.keys.sorted().map { start in
            let group = buckets[start]!
            // Tranche déjà compactée et seule : on la garde telle quelle.
            if group.count == 1, group[0].isCompacted { return group[0] }

            var weightedSum = 0.0
            var weight = 0
            var minT: Int? = nil
            var maxT: Int? = nil
            for s in group {
                guard let t = s.temperatureC else { continue }
                let n = s.measurementCount
                weightedSum += Double(t) * Double(n)
                weight += n
                let lo = s.temperatureMinC ?? t
                let hi = s.temperatureMaxC ?? t
                minT = min(minT ?? lo, lo)
                maxT = max(maxT ?? hi, hi)
            }
            let last = group[group.count - 1]
            return HistorySample(
                date: Date(timeIntervalSince1970: start),
                temperatureC: weight > 0 ? Int((weightedSum / Double(weight)).rounded()) : nil,
                percentageUsed: last.percentageUsed,
                dataUnitsWritten: last.dataUnitsWritten,
                dataUnitsRead: last.dataUnitsRead,
                powerOnHours: last.powerOnHours,
                mediaErrors: last.mediaErrors,
                availableSpare: last.availableSpare,
                temperatureMinC: minT,
                temperatureMaxC: maxT,
                sampleCount: group.reduce(0) { $0 + $1.measurementCount }
            )
        }

        return compacted + recent
    }

    public func samples(for key: String, since: Date) -> [HistorySample] {
        return queue.sync {
            let all = loadRaw(key: key)
            return all.filter { $0.date >= since }
        }
    }

    /// Fusionne un ancien fichier d'historique (même format) dans l'historique de `key`.
    public func importSamples(from url: URL, for key: String) {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([HistorySample].self, from: data),
              !imported.isEmpty else { return }
        queue.sync {
            let existing = loadRaw(key: key)
            var byDate: [Date: HistorySample] = [:]
            for s in imported { byDate[s.date] = s }
            for s in existing { byDate[s.date] = s }
            saveRaw(key: key, samples: byDate.values.sorted { $0.date < $1.date })
        }
    }

    /// Efface tout l'historique de température.
    public func removeAll() {
        queue.sync {
            cache.removeAll()
            let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Taille occupée sur le disque par l'historique, en octets.
    public func diskUsageBytes() -> UInt64 {
        queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + UInt64(size)
            }
        }
    }

    public func folderPath() -> String {
        return historyFolderURL.path
    }
}
