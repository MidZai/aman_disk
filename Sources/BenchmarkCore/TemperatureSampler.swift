import Foundation
import DiskHealthCore

public protocol TemperatureSamplerDelegate: AnyObject {
    func temperatureSamplerDidUpdate(_ temp: Int)
}

/// Relève la température du disque pendant un test de performances (toutes les 2 s en NVMe, 5 s sinon).
///
/// Minuterie GCD sur une file série : l'ancienne version bloquait sa propre file avec
/// `RunLoop.run()`, si bien qu'aucune mesure n'était prise après la première (l'arrêt de sécurité
/// à 70 °C ne pouvait jamais se déclencher) et que le fil et la minuterie fuyaient à chaque test.
public final class TemperatureSampler: @unchecked Sendable {
    private let bsdName: String
    private let protocolType: StorageProtocol
    private let connection: Connection
    private let queue = DispatchQueue(label: "io.github.aman-disk.temperature-sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var knownIdentify: NVMeIdentify?
    private let lock = NSLock()
    private var _currentTempC: Int?
    private var _maxTempC: Int?

    public weak var delegate: TemperatureSamplerDelegate?
    /// Chaque relevé complet, pour que l'historique de température n'ait pas de trou pendant le test.
    public var onSnapshot: ((DiskHealthSnapshot, Date) -> Void)?

    public var currentTempC: Int? { lock.withLock { _currentTempC } }
    public var maxTempC: Int? { lock.withLock { _maxTempC } }

    public init(bsdName: String, protocolType: StorageProtocol, connection: Connection) {
        self.bsdName = bsdName
        self.protocolType = protocolType
        self.connection = connection
    }

    deinit {
        timer?.cancel()
    }

    /// Démarre les mesures. La première est prise immédiatement, de façon synchrone :
    /// la température de départ est donc connue dès le retour de cette fonction.
    public func start() {
        queue.sync { self.sample() }
        let interval: TimeInterval = protocolType == .nvme ? 2.0 : 5.0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        queue.sync { self.timer = t }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    /// À appeler sur `queue`.
    private func sample() {
        let snapshot: DiskHealthSnapshot?
        switch protocolType {
        case .nvme:
            snapshot = try? NVMeBackend.read(bsdName: bsdName, knownIdentify: knownIdentify)
            if case .nvme(_, let identify)? = snapshot { knownIdentify = identify }
        case .ata, .pcieAhci:
            snapshot = try? ATABackend.read(bsdName: bsdName)
        default:
            snapshot = nil
        }
        guard let snapshot else { return }
        onSnapshot?(snapshot, Date())
        guard let t = DiskMetrics(snapshot: snapshot).temperatureC else { return }
        lock.withLock {
            _currentTempC = t
            _maxTempC = max(_maxTempC ?? t, t)
        }
        delegate?.temperatureSamplerDidUpdate(t)
    }
}
