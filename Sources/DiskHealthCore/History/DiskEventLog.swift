import Foundation

/// Notable event in a drive's life, as seen by Aman.
public struct DiskEvent: Codable, Equatable, Hashable {
    public enum Kind: String, Codable {
        /// S.M.A.R.T. was disabled; Aman turned it on.
        case smartEnabled
    }

    public let date: Date
    public let kind: Kind

    public init(date: Date = Date(), kind: Kind) {
        self.date = date
        self.kind = kind
    }
}

/// Event log, one JSON file per drive (same key as the history).
/// In its own folder: clearing the temperature history doesn't clear it.
public final class DiskEventLog: @unchecked Sendable {
    public static var shared = DiskEventLog()

    private let folderURL: URL
    private let lock = NSLock()

    public init(baseURL: URL? = nil) {
        let base = baseURL ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(HistoryStore.defaultFolderName)
        folderURL = base.appendingPathComponent("Events")
    }

    private func fileURL(for key: String) -> URL {
        folderURL.appendingPathComponent("\(key).json")
    }

    public func events(for key: String) -> [DiskEvent] {
        lock.lock(); defer { lock.unlock() }
        return load(key)
    }

    public func append(_ event: DiskEvent, for key: String) {
        lock.lock(); defer { lock.unlock() }
        let events = load(key) + [event]
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    private func load(_ key: String) -> [DiskEvent] {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DiskEvent].self, from: data)) ?? []
    }
}
