import SwiftUI
import DiskHealthCore
import BenchmarkCore

enum BenchUnit {
    case mbps
    case iops
}

@MainActor
class PerformanceViewModel: ObservableObject, BenchmarkRunnerDelegate {
    @Published var selectedTargetId: String = ""
    @Published var targets: [BenchTarget] = []
    @Published var selectedProfile: BenchProfile = .standard
    @Published var selectedSize: UInt64 = 1073741824
    @Published var selectedUnit: BenchUnit = .mbps
    @Published var showConfirm = false
    
    @Published var isRunning = false
    @Published var currentState: BenchmarkState? = nil
    @Published var lastResult: BenchmarkResult? = nil
    
    @Published var history: [BenchmarkResult] = []
    @Published var isViewingHistory: Bool = false
    
    var maxWrittenGB: Double { return 10.0 }
    var estTimeMin: Int { return 1 }
    
    var bottomStripText: String {
        if let res = lastResult {
            let tempStr = res.conditions.temperatureMaxC != nil ? "\(res.conditions.temperatureMaxC!) °C" : "N/A"
            let batStr = res.conditions.onBattery == true ? "Sur batterie" : "Sur secteur"
            var latStr = ""
            if let rnd4k = res.tests.first(where: { $0.spec.id == "RND4K_QD1" && $0.direction == .read }), let p50 = rnd4k.latencyP50Micros, let p99 = rnd4k.latencyP99Micros {
                latStr = " · Latence 4K QD1 : p50 \(Int(p50)) µs / p99 \(Int(p99)) µs"
            }
            return "Température \(tempStr) · Écrit : \(Formatters.bytes(res.conditions.bytesWritten))\(latStr) · \(batStr)"
        } else if currentState != nil {
            return "Test en cours..."
        } else {
            return "Prêt"
        }
    }
    
    let disk: RealDisk
    let appManager: AppManager
    private var runner: BenchmarkRunner?
    
    init(disk: RealDisk, appManager: AppManager) {
        self.disk = disk
        self.appManager = appManager
        refreshTargets()
        loadHistory()
        if let req = appManager.requestedVolumeToTest, let target = targets.first(where: { $0.id == req }) {
            selectedTargetId = target.id
            appManager.requestedVolumeToTest = nil
        } else if let first = targets.first(where: { $0.rejectionReason == nil }) {
            selectedTargetId = first.id
        } else if let first = targets.first {
            selectedTargetId = first.id
        }
    }
    
    public func refreshTargets() {
        let myVols = appManager.volumes.filter { $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
        let pDisks = appManager.disks.map { $0.physical }
        targets = BenchTargetResolver.resolveTargets(volumes: myVols, disks: pDisks, fileSize: selectedSize)
    }
    
    public func loadHistory() {
        BenchmarkHistoryManager.shared.loadResults(forDiskKey: disk.physical.bsdName) { [weak self] res in
            self?.history = res
        }
    }
    
    public func start() {
        guard let t = targets.first(where: { $0.id == selectedTargetId }) else { return }
        isViewingHistory = false
        isRunning = true
        appManager.runningBenchmarkDiskId = disk.id
        lastResult = nil
        currentState = nil
        
        let r = BenchmarkRunner(target: t, profile: selectedProfile, fileSize: selectedSize, physicalDisk: disk.physical)
        r.delegate = self
        self.runner = r
        r.start()
    }
    
    public func stop() {
        runner?.cancel()
    }

    public func startDemo() {
        isRunning = true
        currentState = .preparing(progress: 0.5)
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            var tests: [TestResult] = []
            for spec in BenchTestSpec.defaultGrid {
                let bytes = spec.blockSize == 1048576 ? 3000 * 1048576 : 100 * 1048576
                tests.append(TestResult(spec: spec, direction: .read, passes: [PassResult(bytes: UInt64(bytes), ios: 100, seconds: 1.0)], latencyP50Micros: 100, latencyP99Micros: 200, latencyP999Micros: 400))
                tests.append(TestResult(spec: spec, direction: .write, passes: [PassResult(bytes: UInt64(bytes * 3 / 4), ios: 100, seconds: 1.0)], latencyP50Micros: nil, latencyP99Micros: nil, latencyP999Micros: nil))
            }
            
            let fakeRes = BenchmarkResult(
                id: UUID(),
                date: Date(),
                appVersion: "1.0",
                diskKey: disk.physical.bsdName,
                profile: selectedProfile,
                fileSize: selectedSize,
                conditions: BenchConditions(volumeName: "Macintosh HD", fileSystem: "APFS", encrypted: true, onBattery: false, lowPowerMode: false, thermalStateStart: "Nominal", temperatureStartC: 40, temperatureMaxC: 45, bytesWritten: 0),
                tests: tests,
                completed: true,
                stopReason: nil
            )
            
            DispatchQueue.main.async {
                self.currentState = .done
                self.lastResult = fakeRes
                self.isRunning = false
            }
        }
    }

    nonisolated public func benchmarkDidUpdateState(_ state: BenchmarkState) {
        DispatchQueue.main.async {
            self.currentState = state
        }
    }
    
    nonisolated public func benchmarkDidFinish(result: BenchmarkResult) {
        BenchmarkHistoryManager.shared.saveResult(result, forDiskKey: result.diskKey)
        DispatchQueue.main.async {
            self.lastResult = result
            self.isRunning = false
            self.appManager.runningBenchmarkDiskId = nil
            self.runner = nil
            self.isViewingHistory = false
            self.loadHistory()
        }
    }
}
