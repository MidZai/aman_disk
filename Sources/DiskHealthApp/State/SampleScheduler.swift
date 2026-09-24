import Foundation
import DiskHealthCore

/// Continuous monitoring: one reading of each internal drive every 30 s,
/// as long as the process runs (window open or not).
@MainActor
final class SampleScheduler {
    nonisolated static let interval: TimeInterval = 30
    static let compactionInterval: TimeInterval = 3600

    private weak var appManager: AppManager?
    private var timer: Timer?
    private var isSampling = false
    private var lastCompaction: Date?

    init(appManager: AppManager) {
        self.appManager = appManager
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        // Wide tolerance: lets macOS coalesce wake-ups (idle power use).
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        compactIfNeeded()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        guard let appManager, !isSampling else { return }
        // Suspended during a performance test (its sampler takes over)
        // and during the first load.
        guard !appManager.isBenchmarkRunning, !appManager.isLoading else { return }
        isSampling = true
        defer { isSampling = false }
        await appManager.sampleNow()
        compactIfNeeded()
    }

    private func compactIfNeeded() {
        let now = Date()
        if let last = lastCompaction, now.timeIntervalSince(last) < Self.compactionInterval { return }
        lastCompaction = now
        Task.detached(priority: .utility) {
            HistoryStore.shared.compactAll(now: now)
        }
    }
}
