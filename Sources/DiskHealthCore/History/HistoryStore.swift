import Foundation

/// Historique des relevés, un fichier par disque.
///
/// Format : JSON Lines (`<clé>.jsonl`), une mesure par ligne, en ajout seul. Une mesure toutes les
/// 30 s ajoute donc ~170 octets au fichier, au lieu de réécrire tout l'historique (jusqu'à ~2 Mo
/// au bout de 30 jours, soit plusieurs Go d'écritures par jour sur le SSD surveillé).
/// Le fichier n'est réécrit qu'au compactage, une fois par heure.
///
/// Les anciens fichiers `<clé>.json` (tableau JSON, v0.2 à v0.9) sont convertis à la première lecture.
public final class HistoryStore: @unchecked Sendable {
    /// Remplaçable avant le premier usage (mode démo : dossier temporaire).
    public static var shared = HistoryStore()

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

    // `.utility` et non `.background` : les E/S en QoS « background » sont fortement bridées
    // par macOS, et l'interface attend parfois ces lectures.
    private let queue = DispatchQueue(label: "io.github.aman-disk.history", qos: .utility)
    private let historyFolderURL: URL
    /// Cache mémoire, trié par date : la lecture du fichier n'a lieu qu'une fois par disque.
    private var cache: [String: [HistorySample]] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL? = nil) {
        if let base = baseURL {
            historyFolderURL = base.appendingPathComponent("History")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            historyFolderURL = appSupport.appendingPathComponent(Self.defaultFolderName).appendingPathComponent("History")
        }
        try? FileManager.default.createDirectory(at: historyFolderURL, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - Fichiers

    private func fileURL(for key: String) -> URL {
        historyFolderURL.appendingPathComponent("\(key).jsonl")
    }

    private func legacyFileURL(for key: String) -> URL {
        historyFolderURL.appendingPathComponent("\(key).json")
    }

    /// À appeler sur `queue`.
    private func loadRaw(key: String) -> [HistorySample] {
        if let cached = cache[key] { return cached }
        var samples: [HistorySample] = []
        let url = fileURL(for: key)
        if let data = try? Data(contentsOf: url) {
            samples = decodeLines(data)
        }
        // Ancien format : tableau JSON. Converti une fois, puis supprimé.
        let legacyURL = legacyFileURL(for: key)
        if let data = try? Data(contentsOf: legacyURL) {
            let legacy = (try? decoder.decode([HistorySample].self, from: data)) ?? []
            samples = Self.merge(legacy, samples)
            writeAll(key: key, samples: samples)
            try? FileManager.default.removeItem(at: legacyURL)
        }
        samples.sort { $0.date < $1.date }
        cache[key] = samples
        return samples
    }

    private func decodeLines(_ data: Data) -> [HistorySample] {
        var samples: [HistorySample] = []
        samples.reserveCapacity(data.count / 160)
        // Une ligne tronquée (coupure de courant pendant l'écriture) est simplement ignorée.
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            if let s = try? decoder.decode(HistorySample.self, from: Data(line)) {
                samples.append(s)
            }
        }
        return samples
    }

    /// Réécrit tout le fichier (compactage, fusion, conversion). À appeler sur `queue`.
    private func writeAll(key: String, samples: [HistorySample]) {
        cache[key] = samples
        var data = Data()
        data.reserveCapacity(samples.count * 170)
        for s in samples {
            guard let line = try? encoder.encode(s) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Ajoute une ligne en fin de fichier. À appeler sur `queue`.
    private func appendLine(key: String, sample: HistorySample) {
        guard var line = try? encoder.encode(sample) else { return }
        line.append(UInt8(ascii: "\n"))
        let url = fileURL(for: key)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                return
            } catch {
                // Repli ci-dessous : réécriture complète.
            }
        }
        writeAll(key: key, samples: cache[key] ?? [sample])
    }

    private static func merge(_ a: [HistorySample], _ b: [HistorySample]) -> [HistorySample] {
        var byDate: [Date: HistorySample] = [:]
        for s in a { byDate[s.date] = s }
        for s in b { byDate[s.date] = s }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Ajoute une mesure (déjà filtrée). À appeler sur `queue`.
    /// La durée de conservation est appliquée par le compactage horaire, pas à chaque mesure.
    private func add(_ sample: HistorySample, key: String) {
        var samples = loadRaw(key: key)
        if let last = samples.last, sample.date < last.date {
            // Mesure plus ancienne que la dernière (horloge modifiée) : insérée à sa place.
            samples.append(sample)
            samples.sort { $0.date < $1.date }
            writeAll(key: key, samples: samples)
            return
        }
        samples.append(sample)
        cache[key] = samples
        appendLine(key: key, sample: sample)
    }

    // MARK: - Écriture

    /// Ajout historique (v0.2) : rejette les mesures à moins de 4 min et 3 °C de la précédente.
    public func append(_ sample: HistorySample, for key: String) {
        queue.async {
            if let last = self.loadRaw(key: key).last {
                let timeDiff = sample.date.timeIntervalSince(last.date)
                if timeDiff > 0 && timeDiff < (4 * 60) {
                    let tempDiff = abs((sample.temperatureC ?? 0) - (last.temperatureC ?? 0))
                    if tempDiff < 3 { return }
                }
            }
            self.add(sample, key: key)
            // Comportement v0.2 : purge immédiate des mesures trop anciennes.
            let cutoff = Date().addingTimeInterval(-Self.retention)
            if let first = self.cache[key]?.first, first.date < cutoff {
                self.writeAll(key: key, samples: (self.cache[key] ?? []).filter { $0.date >= cutoff })
            }
        }
    }

    /// Ajout en pleine résolution, utilisé par la surveillance continue (une mesure toutes les 30 s).
    /// Seuls les doublons (moins de 15 s d'écart) sont ignorés.
    public func record(_ sample: HistorySample, for key: String) {
        queue.async {
            if let last = self.loadRaw(key: key).last, abs(sample.date.timeIntervalSince(last.date)) < Self.minimumSpacing {
                return
            }
            self.add(sample, key: key)
        }
    }

    /// Compacte tous les historiques : pleine résolution sur 24 h, tranches de 5 min jusqu'à 30 jours.
    public func compactAll(now: Date = Date()) {
        queue.sync {
            for key in self.allKeys() {
                let samples = loadRaw(key: key)
                let compacted = Self.compact(samples, now: now)
                if compacted != samples {
                    writeAll(key: key, samples: compacted)
                }
            }
        }
    }

    /// Clés présentes sur le disque (nouveau et ancien format) ou en mémoire. À appeler sur `queue`.
    private func allKeys() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil)) ?? []
        let onDisk = files
            .filter { $0.pathExtension == "jsonl" || $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Set(onDisk).union(cache.keys)
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

        let compacted: [HistorySample] = buckets.keys.sorted().compactMap { start in
            guard let group = buckets[start], let last = group.last else { return nil }
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

    // MARK: - Lecture

    /// Lecture synchrone (outil en ligne de commande, tests). Depuis l'interface, préférer la version `async`.
    public func samples(for key: String, since: Date) -> [HistorySample] {
        queue.sync { Self.suffix(of: loadRaw(key: key), since: since) }
    }

    /// Lecture sans bloquer le fil principal.
    public func loadSamples(for key: String, since: Date) async -> [HistorySample] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.suffix(of: self.loadRaw(key: key), since: since))
            }
        }
    }

    /// Mesures postérieures à `since` dans un tableau trié (recherche dichotomique).
    private static func suffix(of sorted: [HistorySample], since: Date) -> [HistorySample] {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].date < since { lo = mid + 1 } else { hi = mid }
        }
        return Array(sorted[lo...])
    }

    /// Fusionne un ancien fichier d'historique (tableau JSON) dans l'historique de `key`.
    public func importSamples(from url: URL, for key: String) {
        guard let data = try? Data(contentsOf: url),
              let imported = try? decoder.decode([HistorySample].self, from: data),
              !imported.isEmpty else { return }
        queue.sync {
            let existing = loadRaw(key: key)
            writeAll(key: key, samples: Self.merge(imported, existing))
        }
    }

    /// Efface tout l'historique de température.
    public func removeAll() {
        queue.sync {
            cache.removeAll()
            let files = (try? FileManager.default.contentsOfDirectory(at: historyFolderURL, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" || file.pathExtension == "json" {
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
        historyFolderURL.path
    }
}
