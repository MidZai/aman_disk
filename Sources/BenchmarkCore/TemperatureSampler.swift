import Foundation
import DiskHealthCore

public protocol TemperatureSamplerDelegate: AnyObject {
    func temperatureSamplerDidUpdate(_ temp: Int)
}

/// Records the drive temperature during a performance test (every 2 s for NVMe, 5 s otherwise).
///
/// GCD timer on a serial queue: the old version blocked its own queue with
/// `RunLoop.run()`, so no reading was taken after the first one (the safety stop at
/// 70 °C could never trigger), and the thread and timer leaked on every test.
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
    /// Every full reading, so the temperature history has no gap during the test.
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

    /// Starts the readings. The first one is taken immediately and synchronously,
    /// so the starting temperature is known as soon as this function returns.
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

    /// Call on `queue`.
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
