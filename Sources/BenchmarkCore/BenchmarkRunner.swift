import Foundation
import DiskHealthCore
import CBenchIO
import IOKit.ps

public enum BenchmarkState {
    case preparing(progress: Double) // 0...1
    case pass(testId: String, pass: Int, totalPasses: Int, progress: Double, speedMBps: Double?)
    case paused(secondsRemaining: Double)
    case done
    case error(Error)
}

public protocol BenchmarkRunnerDelegate: AnyObject {
    func benchmarkDidUpdateState(_ state: BenchmarkState)
    func benchmarkDidFinish(result: BenchmarkResult)
}

public class BenchmarkRunner: TemperatureSamplerDelegate {
    private let target: BenchTarget
    private let profile: BenchProfile
    private let specGrid: [BenchTestSpec]
    private let fileSize: UInt64
    private let physicalDisk: PhysicalDisk
    
    public weak var delegate: BenchmarkRunnerDelegate?
    
    private var isCancelled = false
    private let queue = DispatchQueue(label: "io.github.aman-disk.BenchmarkRunner")
    private var tempSampler: TemperatureSampler?
    private var activityId: NSObjectProtocol?
        private struct SafeCtx: @unchecked Sendable {
        let pointer: OpaquePointer?
    }
    private var ctx: OpaquePointer?
    
    private var testsResults: [TestResult] = []
    private var stopReason: String?
    
    // For 10Hz state updates
    private let stateLock = NSLock()
    private var currentState: BenchmarkState?
    private var stateTimer: Timer?
    
    public init(target: BenchTarget, profile: BenchProfile, fileSize: UInt64, physicalDisk: PhysicalDisk, specGrid: [BenchTestSpec] = BenchTestSpec.defaultGrid) {
        self.target = target
        self.profile = profile
        self.fileSize = fileSize
        self.physicalDisk = physicalDisk
        self.specGrid = specGrid
    }
    
    public func start() {
        DispatchQueue.main.async {
            self.stateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.stateLock.lock()
                let st = self.currentState
                self.stateLock.unlock()
                if let s = st {
                    self.delegate?.benchmarkDidUpdateState(s)
                }
            }
        }
        queue.async {
            self.run()
        }
    }
    
    public func cancel() {
        queue.async {
            self.isCancelled = true
            if let c = self.ctx {
                cbench_ctx_cancel(c)
            }
        }
    }
    
    public func temperatureSamplerDidUpdate(_ temp: Int) {
        if temp >= 70 {
            queue.async {
                if self.stopReason == nil && !self.isCancelled {
                    self.stopReason = "temperature"
                    self.isCancelled = true
                    if let c = self.ctx {
                        cbench_ctx_cancel(c)
                    }
                }
            }
        }
    }
    
    private func setState(_ state: BenchmarkState) {
        stateLock.lock()
        currentState = state
        stateLock.unlock()
    }
    
    private func recordInflight(path: String) {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "io.github.aman-disk.AmanDisk"
        let dir = appSupport.appendingPathComponent(bundleId)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let fileURL = dir.appendingPathComponent("bench-inflight.json")
        var current: [String] = []
        if let data = try? Data(contentsOf: fileURL), let arr = try? JSONDecoder().decode([String].self, from: data) {
            current = arr
        }
        if !current.contains(path) {
            current.append(path)
            if let data = try? JSONEncoder().encode(current) {
                try? data.write(to: fileURL)
            }
        }
    }
    
    private func removeInflight(path: String) {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "io.github.aman-disk.AmanDisk"
        let fileURL = appSupport.appendingPathComponent(bundleId).appendingPathComponent("bench-inflight.json")
        
        var current: [String] = []
        if let data = try? Data(contentsOf: fileURL), let arr = try? JSONDecoder().decode([String].self, from: data) {
            current = arr
        }
        if let idx = current.firstIndex(of: path) {
            current.remove(at: idx)
            if let data = try? JSONEncoder().encode(current) {
                try? data.write(to: fileURL)
            }
        }
    }
    
        private func getPowerSource() -> String {
        return IOPSGetProvidingPowerSourceType(nil).takeRetainedValue() as String
    }
    
    private func getThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
    
    private func run() {
        let path = target.testDirectoryURL.appendingPathComponent("DiskHealthBench-\\(UUID().uuidString).tmp").path
        recordInflight(path: path)
        
        activityId = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Test de performances Aman Disk")
        
        tempSampler = TemperatureSampler(bsdName: physicalDisk.bsdName, protocolType: physicalDisk.protocolType, connection: physicalDisk.connection)
        tempSampler?.delegate = self
        tempSampler?.start()
        
        let startTemp = tempSampler?.currentTempC
        
        ctx = cbench_ctx_create()
        defer {
            if let c = ctx { cbench_ctx_destroy(c) }
            tempSampler?.stop()
            if let aid = activityId {
                ProcessInfo.processInfo.endActivity(aid)
            }
            try? FileManager.default.removeItem(atPath: path)
            removeInflight(path: path)
            
            var bytesWritten: UInt64 = fileSize // Prepare file
            for r in testsResults where r.direction == .write {
                for p in r.passes {
                    bytesWritten += p.bytes
                }
            }
            
            let cond = BenchConditions(
                volumeName: target.volume.name,
                fileSystem: target.fileSystem,
                encrypted: target.isEncrypted,
                onBattery: getPowerSource().contains("Battery"),
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalStateStart: getThermalState(),
                temperatureStartC: startTemp,
                temperatureMaxC: tempSampler?.maxTempC,
                bytesWritten: bytesWritten
            )
            
            let result = BenchmarkResult(
                id: UUID(),
                date: Date(),
                appVersion: "0.9.0",
                diskKey: DiskIdentity.key(model: physicalDisk.model, serial: ""),
                profile: profile,
                fileSize: fileSize,
                conditions: cond,
                tests: testsResults,
                completed: stopReason == nil && !isCancelled,
                stopReason: isCancelled && stopReason == nil ? "cancelled" : stopReason
            )
            
            setState(.done)
            DispatchQueue.main.async {
                self.stateTimer?.invalidate()
                self.stateTimer = nil
                self.delegate?.benchmarkDidFinish(result: result)
            }
        }
        
        // Spawn a monitoring thread for progress
        let ctxToMonitor = ctx!
        let isCancelledRef = { self.isCancelled }
        
        var isPreparing = true
        let safeCtxMon = SafeCtx(pointer: ctxToMonitor)
        let monThread = Thread {
            while isPreparing && !isCancelledRef() {
                let bytes = cbench_ctx_progress_bytes(safeCtxMon.pointer)
                let prog = Double(bytes) / Double(self.fileSize)
                self.setState(.preparing(progress: min(1.0, max(0.0, prog))))
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        monThread.start()
        
        let err = cbench_prepare_file(ctx, path, fileSize)
        isPreparing = false
        
        if err != 0 {
            if err == -100 { stopReason = "cancelled" }
            else { stopReason = "error:\\(err)" }
            return
        }
        
        let readDirections: [BenchDirection] = [.read]
        let writeDirections: [BenchDirection] = profile.includesWrites ? [.write] : []
        let directions = readDirections + writeDirections
        
        for dir in directions {
            for spec in specGrid {
                if isCancelled { return }
                
                var passResults: [PassResult] = []
                var allLatencies: [UInt64] = []
                let patStr = spec.pattern == .sequential ? "SEQ" : "RND"; let blkStr = spec.blockSize >= 1048576 ? "\(spec.blockSize/1048576)M" : "\(spec.blockSize/1024)K"; let testId = "\(patStr) \(blkStr) QD\(spec.queueDepth)"
                
                for passNum in 1...profile.passes {
                    if isCancelled { return }
                    
                    var params = cbench_params(
                        pattern: spec.pattern == .sequential ? CBENCH_SEQ : CBENCH_RND,
                        direction: dir == .read ? CBENCH_READ : CBENCH_WRITE,
                        block_size: UInt32(spec.blockSize),
                        queue_depth: UInt32(spec.queueDepth),
                        file_size: fileSize,
                        max_seconds: profile.timedPassSeconds,
                        max_bytes: (spec.pattern == .random) ? fileSize : 0 // max_bytes = filesize for RND
                    )
                    
                    var outRes = cbench_result()
                    
                    let useLat = spec.recordsLatency && spec.queueDepth == 1
                    var lats = useLat ? [UInt64](repeating: 0, count: 1_000_000) : []
                    var latCount: UInt64 = 0
                    
                    var isPassing = true
                    let safeCtxPass = SafeCtx(pointer: ctxToMonitor)
                    let passMon = Thread {
                        let passStart = Date()
                        while isPassing && !isCancelledRef() {
                            let bytes = cbench_ctx_progress_bytes(safeCtxPass.pointer)
                            let elapsed = Date().timeIntervalSince(passStart)
                            
                            var prog: Double = 0
                            if params.max_seconds > 0 {
                                prog = elapsed / params.max_seconds
                            }
                            // Speed in MB/s
                            let speed = elapsed > 0 ? (Double(bytes) / elapsed) / 1_000_000.0 : 0
                            
                            self.setState(.pass(testId: testId, pass: passNum, totalPasses: self.profile.passes, progress: min(1.0, max(0.0, prog)), speedMBps: speed))
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                    }
                    passMon.start()
                    
                                        let pErr: Int32
                    if useLat {
                        pErr = lats.withUnsafeMutableBufferPointer { ptr in
                            cbench_run_pass(ctx, path, &params, &outRes, ptr.baseAddress, UInt64(ptr.count), &latCount)
                        }
                    } else {
                        pErr = cbench_run_pass(ctx, path, &params, &outRes, nil, 0, &latCount)
                    }
                    isPassing = false
                    
                    if pErr != 0 || outRes.error != 0 {
                        let e = outRes.error != 0 ? outRes.error : pErr
                        stopReason = e == -100 ? "cancelled" : "error:\\(e)"
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
                
                // Pause
                if !isCancelled && !(dir == directions.last && spec == specGrid.last) {
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
}
