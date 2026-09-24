import Foundation
import DiskHealthCore
import CBenchIO
import IOKit.ps

public enum BenchmarkState {
    case preparing(progress: Double) // 0...1
    case pass(specId: String, direction: BenchDirection, pass: Int, totalPasses: Int, progress: Double, speedMBps: Double?)
    case paused(secondsRemaining: Double)
    case done
    case error(Error)
}

/// Toutes les méthodes sont appelées sur le fil principal.
public protocol BenchmarkRunnerDelegate: AnyObject {
    func benchmarkDidUpdateState(_ state: BenchmarkState)
    /// Un test (motif × sens) vient de se terminer : la grille peut l'afficher sans attendre la fin.
    func benchmarkDidComplete(test: TestResult)
    func benchmarkDidFinish(result: BenchmarkResult)
}

public extension BenchmarkRunnerDelegate {
    func benchmarkDidComplete(test: TestResult) {}
}

/// Fichiers de test en cours : si l'app s'arrête brutalement, ils sont supprimés au lancement suivant.
public enum BenchInflight {
    static var fileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let bundleId = Bundle.main.bundleIdentifier ?? HistoryStore.defaultFolderName
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("bench-inflight.json")
    }

    static func read() -> [String] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func write(_ paths: [String]) {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if paths.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Supprime les fichiers de test laissés par un test interrompu (plantage, arrêt forcé).
    public static func cleanUpLeftovers() {
        for path in read() {
            try? FileManager.default.removeItem(atPath: path)
        }
        write([])
    }
}

public final class BenchmarkRunner: TemperatureSamplerDelegate, @unchecked Sendable {
    /// Au-delà, le test s'arrête pour protéger le disque.
    public static let temperatureLimitC = 70

    private let target: BenchTarget
    private let profile: BenchProfile
    private let specGrid: [BenchTestSpec]
    private let fileSize: UInt64
    private let physicalDisk: PhysicalDisk
    private let diskKey: String
    private let appVersion: String

    public weak var delegate: BenchmarkRunnerDelegate?
    /// Relevés pris pendant le test (pour l'historique de température).
    public var onTemperatureSnapshot: ((DiskHealthSnapshot, Date) -> Void)?

    private let queue = DispatchQueue(label: "io.github.aman-disk.benchmark", qos: .userInitiated)
    private let lock = NSLock()
    // Partagés entre la file du test, le fil principal et l'échantillonneur : protégés par `lock`.
    private var _cancelled = false
    private var _stopReason: String?
    private var _ctx: OpaquePointer?
    private var _currentState: BenchmarkState?
    private var _stateChanged = false

    private var stateTimer: DispatchSourceTimer?
    private var tempSampler: TemperatureSampler?
    private var testsResults: [TestResult] = []

    public init(target: BenchTarget, profile: BenchProfile, fileSize: UInt64, physicalDisk: PhysicalDisk,
                diskKey: String? = nil, appVersion: String? = nil,
                specGrid: [BenchTestSpec] = BenchTestSpec.defaultGrid) {
        self.target = target
        self.profile = profile
        self.fileSize = fileSize
        self.physicalDisk = physicalDisk
        self.specGrid = specGrid
        self.diskKey = diskKey ?? DiskIdentity.key(model: physicalDisk.model, serial: "")
        self.appVersion = appVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "dev"
    }

    private var isCancelled: Bool { lock.withLock { _cancelled } }

    public func start() {
        // État publié au plus 10 fois par seconde, seulement s'il a changé.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let state: BenchmarkState? = self.lock.withLock {
                guard self._stateChanged else { return nil }
                self._stateChanged = false
                return self._currentState
            }
            if let state { self.delegate?.benchmarkDidUpdateState(state) }
        }
        t.resume()
        stateTimer = t
        queue.async { self.run() }
    }

    /// Sûr depuis n'importe quel fil.
    public func cancel() {
        stop(reason: nil)
    }

    private func stop(reason: String?) {
        lock.withLock {
            guard !_cancelled else { return }
            _cancelled = true
            if let reason, _stopReason == nil { _stopReason = reason }
            if let c = _ctx { cbench_ctx_cancel(c) }
        }
    }

    public func temperatureSamplerDidUpdate(_ temp: Int) {
        if temp >= Self.temperatureLimitC {
            stop(reason: "temperature")
        }
    }

    private func setState(_ state: BenchmarkState) {
        lock.withLock {
            _currentState = state
            _stateChanged = true
        }
    }

    private func powerSourceIsBattery() -> Bool {
        guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else { return false }
        return source.contains("Battery")
    }

    private func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func run() {
        let path = target.testDirectoryURL.appendingPathComponent("DiskHealthBench-\(UUID().uuidString).tmp").path
        BenchInflight.write(BenchInflight.read() + [path])
        let thermalStart = thermalState()
        let onBattery = powerSourceIsBattery()

        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: L("Aman Disk performance test", "Test de performances Aman Disk"))

        let sampler = TemperatureSampler(bsdName: physicalDisk.bsdName, protocolType: physicalDisk.protocolType, connection: physicalDisk.connection)
        sampler.delegate = self
        sampler.onSnapshot = onTemperatureSnapshot
        sampler.start()
        tempSampler = sampler
        let startTemp = sampler.currentTempC

        guard let ctx = cbench_ctx_create() else {
            stop(reason: "error:ENOMEM")
            finish(path: path, activity: activity, startTemp: startTemp, thermalStart: thermalStart, onBattery: onBattery)
            return
        }
        lock.withLock { _ctx = ctx }
        defer {
            lock.withLock { _ctx = nil }
            cbench_ctx_destroy(ctx)
        }
        // Une annulation arrivée avant la création du contexte doit aussi arrêter le C.
        if isCancelled { cbench_ctx_cancel(ctx) }

        runTests(ctx: ctx, path: path)
        finish(path: path, activity: activity, startTemp: startTemp, thermalStart: thermalStart, onBattery: onBattery)
    }

    /// Progression lue dans le contexte C pendant qu'il travaille, sans fil dédié.
    private func startProgressMonitor(ctx: OpaquePointer, _ makeState: @escaping (_ bytes: UInt64, _ elapsed: Double) -> BenchmarkState) -> DispatchSourceTimer {
        let started = DispatchTime.now()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: 0.1, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
            self?.setState(makeState(cbench_ctx_progress_bytes(ctx), elapsed))
        }
        t.resume()
        return t
    }

    private func runTests(ctx: OpaquePointer, path: String) {
        let fileSize = self.fileSize
        let prepMonitor = startProgressMonitor(ctx: ctx) { bytes, _ in
            .preparing(progress: min(1, Double(bytes) / Double(max(fileSize, 1))))
        }
        let err = cbench_prepare_file(ctx, path, fileSize)
        prepMonitor.cancel()
        if err != 0 {
            stop(reason: err == -100 ? nil : "error:\(err)")
            return
        }

        let directions: [BenchDirection] = profile.includesWrites ? [.read, .write] : [.read]
        let totalTests = directions.count * specGrid.count
        var testIndex = 0

        for dir in directions {
            for spec in specGrid {
                testIndex += 1
                if isCancelled { return }

                var passResults: [PassResult] = []
                var allLatencies: [UInt64] = []
                let useLat = spec.recordsLatency && spec.queueDepth == 1
                // Tampon de latences alloué une fois par test, pas à chaque passe.
                var lats = useLat ? [UInt64](repeating: 0, count: 1_000_000) : []

                for passNum in 1...profile.passes {
                    if isCancelled { return }

                    var params = cbench_params(
                        pattern: spec.pattern == .sequential ? CBENCH_SEQ : CBENCH_RND,
                        direction: dir == .read ? CBENCH_READ : CBENCH_WRITE,
                        block_size: UInt32(spec.blockSize),
                        queue_depth: UInt32(spec.queueDepth),
                        file_size: fileSize,
                        max_seconds: profile.timedPassSeconds,
                        max_bytes: spec.pattern == .random ? fileSize : 0
                    )
                    let maxSeconds = params.max_seconds
                    let passes = profile.passes
                    let monitor = startProgressMonitor(ctx: ctx) { bytes, elapsed in
                        .pass(specId: spec.id, direction: dir, pass: passNum, totalPasses: passes,
                              progress: maxSeconds > 0 ? min(1, elapsed / maxSeconds) : 0,
                              speedMBps: elapsed > 0 ? Double(bytes) / elapsed / 1_000_000 : nil)
                    }

                    var outRes = cbench_result()
                    var latCount: UInt64 = 0
                    let pErr: Int32 = useLat
                        ? lats.withUnsafeMutableBufferPointer { ptr in
                            cbench_run_pass(ctx, path, &params, &outRes, ptr.baseAddress, UInt64(ptr.count), &latCount)
                        }
                        : cbench_run_pass(ctx, path, &params, &outRes, nil, 0, &latCount)
                    monitor.cancel()

                    if pErr != 0 || outRes.error != 0 {
                        let e = outRes.error != 0 ? outRes.error : pErr
                        stop(reason: e == -100 ? nil : "error:\(e)")
                        return
                    }

                    passResults.append(PassResult(bytes: outRes.bytes, ios: outRes.ios, seconds: outRes.seconds))
                    if useLat && latCount > 0 {
                        allLatencies.append(contentsOf: lats.prefix(Int(latCount)))
                    }
                }

                allLatencies.sort()
                let tr = TestResult(
                    spec: spec,
                    direction: dir,
                    passes: passResults,
                    latencyP50Micros: BenchMath.percentile(allLatencies, 50.0),
                    latencyP99Micros: BenchMath.percentile(allLatencies, 99.0),
                    latencyP999Micros: BenchMath.percentile(allLatencies, 99.9)
                )
                testsResults.append(tr)
                DispatchQueue.main.async { [weak self] in self?.delegate?.benchmarkDidComplete(test: tr) }

                // Pause entre deux tests : laisse le contrôleur vider son cache et refroidir.
                if testIndex < totalTests {
                    var remaining = profile.pauseSeconds
                    while remaining > 0 && !isCancelled {
                        setState(.paused(secondsRemaining: remaining))
                        Thread.sleep(forTimeInterval: 0.1)
                        remaining -= 0.1
                    }
                }
            }
        }
    }

    private func finish(path: String, activity: NSObjectProtocol, startTemp: Int?, thermalStart: String, onBattery: Bool) {
        tempSampler?.stop()
        ProcessInfo.processInfo.endActivity(activity)
        try? FileManager.default.removeItem(atPath: path)
        BenchInflight.write(BenchInflight.read().filter { $0 != path })

        var bytesWritten: UInt64 = fileSize // fichier de test
        for r in testsResults where r.direction == .write {
            for p in r.passes { bytesWritten &+= p.bytes }
        }

        let (cancelled, stopReason) = lock.withLock { (_cancelled, _stopReason) }
        let cond = BenchConditions(
            volumeName: target.volume.name,
            fileSystem: target.fileSystem,
            encrypted: target.isEncrypted,
            onBattery: onBattery,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalStateStart: thermalStart,
            temperatureStartC: startTemp,
            temperatureMaxC: tempSampler?.maxTempC,
            bytesWritten: bytesWritten
        )
        let result = BenchmarkResult(
            id: UUID(),
            date: Date(),
            appVersion: appVersion,
            diskKey: diskKey,
            profile: profile,
            fileSize: fileSize,
            conditions: cond,
            tests: testsResults,
            completed: !cancelled,
            stopReason: cancelled ? (stopReason ?? "cancelled") : nil
        )

        setState(.done)
        DispatchQueue.main.async {
            self.stateTimer?.cancel()
            self.stateTimer = nil
            self.delegate?.benchmarkDidUpdateState(.done)
            self.delegate?.benchmarkDidFinish(result: result)
        }
    }
}
