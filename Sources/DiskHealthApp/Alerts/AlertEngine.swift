import Foundation
import DiskHealthCore

/// Relevé d'un disque, réduit à ce dont les alertes ont besoin.
struct AlertReading: Equatable {
    let diskId: String
    let name: String
    let status: HealthStatus
    let firstReason: String?
    let temperatureC: Int?
    let isRotational: Bool
    /// Durée de vie restante en %, seulement si le disque la fournit.
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

/// Envoie une notification système (remplacé par un faux dans les tests).
protocol NotificationPosting: AnyObject {
    func post(_ event: AlertEvent)
}

/// Détecte les événements à notifier. Une notification par événement, jamais de répétition.
/// L'état est `Codable` pour survivre à un redémarrage de l'app.
final class AlertEngine {
    static let overheatDuration: TimeInterval = 5 * 60
    static let ssdThreshold = 60
    static let hddThreshold = 55
    static let rearmMargin = 5
    static let lifeThresholds = [50, 25, 10]
    /// Au-delà de cet écart sans relevé (app fermée, veille), la durée de chauffe repart de zéro.
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
    /// Quand faux, l'état est suivi mais rien n'est envoyé (évite une rafale à l'activation).
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
        // Premier relevé : sert de référence, pas d'alerte.
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
            // Redescendu sous le seuil moins 5 °C : une nouvelle alerte redevient possible.
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
            // Premier relevé : les seuils déjà franchis ne sont pas signalés.
            state.notifiedLifeThresholds.formUnion(Self.lifeThresholds.filter { life <= $0 })
            return []
        }
        let crossed = Self.lifeThresholds.filter { previous > $0 && life <= $0 && !state.notifiedLifeThresholds.contains($0) }
        guard let lowest = crossed.min() else { return [] }
        state.notifiedLifeThresholds.formUnion(crossed)
        return [AlertEvent(diskId: r.diskId, kind: .lifeThreshold(lowest), message: L("\(r.name): remaining life dropped below \(lowest)% (\(life)%).", "\(r.name) : durée de vie restante passée sous \(lowest) % (\(life) %)."))]
    }
}
