import Foundation
import DiskHealthCore

/// A drive reading, reduced to what the alerts need.
struct AlertReading: Equatable {
    let diskId: String
    let name: String
    let status: HealthStatus
    let firstReason: String?
    let temperatureC: Int?
    let isRotational: Bool
    /// Remaining life in %, only if the drive reports it.
    let lifePercent: Int?
}

struct AlertEvent: Equatable {
    enum Kind: Equatable {
        case status(HealthStatus)
        case overheat
        case lifeThreshold(Int)
    }
    let diskId: String
    let kind: Kind
    let message: String
}

/// Posts a system notification (replaced by a fake in the tests).
protocol NotificationPosting: AnyObject {
    func post(_ event: AlertEvent)
}

/// Detects the events to notify. One notification per event, never repeated.
/// The state is `Codable` so it survives an app restart.
final class AlertEngine {
    static let overheatDuration: TimeInterval = 5 * 60
    static let ssdThreshold = 60
    static let hddThreshold = 55
    static let rearmMargin = 5
    static let lifeThresholds = [50, 25, 10]
    /// Beyond this gap without a reading (app closed, sleep), the overheating timer starts over.
    static let maxReadingGap: TimeInterval = 3 * SampleScheduler.interval

    struct DiskState: Codable, Equatable {
        var status: HealthStatus?
        var hotSince: Date?
        var overheatNotified = false
        var lastLifePercent: Int?
        var notifiedLifeThresholds: Set<Int> = []
        var lastSeen: Date?
    }

    private(set) var states: [String: DiskState]
    private let clock: () -> Date
    private weak var poster: NotificationPosting?
    /// When false, the state is tracked but nothing is posted (avoids a burst when alerts are turned on).
    var isEnabled: Bool

    init(poster: NotificationPosting?, clock: @escaping () -> Date = Date.init, states: [String: DiskState] = [:], isEnabled: Bool = true) {
        self.poster = poster
        self.clock = clock
        self.states = states
        self.isEnabled = isEnabled
    }

    @discardableResult
    func process(_ readings: [AlertReading]) -> [AlertEvent] {
        let now = clock()
        var events: [AlertEvent] = []
        for reading in readings {
            var state = states[reading.diskId] ?? DiskState()
            if let seen = state.lastSeen, now.timeIntervalSince(seen) > Self.maxReadingGap {
                state.hotSince = nil
            }
            state.lastSeen = now
            events += statusEvents(reading, &state)
            events += temperatureEvents(reading, &state, now: now)
            events += lifeEvents(reading, &state)
            states[reading.diskId] = state
        }
        if isEnabled {
            events.forEach { poster?.post($0) }
        }
        return isEnabled ? events : []
    }

    private func statusEvents(_ r: AlertReading, _ state: inout DiskState) -> [AlertEvent] {
        defer { state.status = r.status }
        // First reading: used as the baseline, no alert.
        guard let previous = state.status, previous != r.status else { return [] }
        guard r.status == .caution || r.status == .bad else { return [] }
        var message = L("\(r.name): \(r.status.localizedLabel).", "\(r.name) : \(r.status.localizedLabel).")
        if let reason = r.firstReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            message += " \(reason)"
            if !reason.hasSuffix(".") { message += "." }
        }
        return [AlertEvent(diskId: r.diskId, kind: .status(r.status), message: message)]
    }

    private func temperatureEvents(_ r: AlertReading, _ state: inout DiskState, now: Date) -> [AlertEvent] {
        guard let t = r.temperatureC else { return [] }
        let threshold = r.isRotational ? Self.hddThreshold : Self.ssdThreshold

        if t < threshold - Self.rearmMargin {
            // Back below the threshold minus 5 °C: a new alert becomes possible again.
            state.overheatNotified = false
        }
        guard t > threshold else {
            state.hotSince = nil
            return []
        }
        let since = state.hotSince ?? now
        state.hotSince = since
        guard !state.overheatNotified, now.timeIntervalSince(since) >= Self.overheatDuration else { return [] }
        state.overheatNotified = true
        return [AlertEvent(diskId: r.diskId, kind: .overheat, message: L("\(r.name) is running hot: \(t) °C for 5 minutes.", "\(r.name) chauffe : \(t) °C depuis 5 minutes."))]
    }

    private func lifeEvents(_ r: AlertReading, _ state: inout DiskState) -> [AlertEvent] {
        guard let life = r.lifePercent else { return [] }
        defer { state.lastLifePercent = life }
        guard let previous = state.lastLifePercent else {
            // First reading: thresholds already crossed are not reported.
            state.notifiedLifeThresholds.formUnion(Self.lifeThresholds.filter { life <= $0 })
            return []
        }
        let crossed = Self.lifeThresholds.filter { previous > $0 && life <= $0 && !state.notifiedLifeThresholds.contains($0) }
        guard let lowest = crossed.min() else { return [] }
        state.notifiedLifeThresholds.formUnion(crossed)
        return [AlertEvent(diskId: r.diskId, kind: .lifeThreshold(lowest), message: L("\(r.name): remaining life dropped below \(lowest)% (\(life)%).", "\(r.name) : durée de vie restante passée sous \(lowest) % (\(life) %)."))]
    }
}
