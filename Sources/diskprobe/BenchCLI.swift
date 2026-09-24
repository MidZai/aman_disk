import Foundation
import DiskHealthCore
import BenchmarkCore

enum BenchCLI {
    static func run(args: [String]) {
        let volumes = VolumeDiscovery.listVolumes()
        let disks = DiskDiscovery.listPhysicalDisks()
        
        BenchCleanup.run(volumes: volumes)
        BenchInflight.cleanUpLeftovers()
        
        if args.contains("--list-targets") {
            let targets = BenchTargetResolver.resolveTargets(volumes: volumes, disks: disks)
            for target in targets {
                if let reason = target.rejectionReason {
                    var rStr = ""
                    switch reason {
                    case .readOnly: rStr = "Read-only"
                    case .network: rStr = "Network volume"
                    case .diskImage: rStr = "Disk image"
                    case .timeMachine: rStr = "Time Machine backup"
                    case .accessDenied: rStr = "Access denied"
                    case .insufficientFreeSpace(let v): rStr = "Not enough free space (\(v))"
                    }
                    print("\(target.volume.mountPoint): NO (\(rStr))")
                } else {
                    print("\(target.volume.mountPoint): YES")
                }
            }
            exit(0)
        }
        
        var profile = BenchProfile.standard
        let pIdx = args.firstIndex(of: "--profile") ?? -1
        if pIdx >= 0, pIdx + 1 < args.count {
            let pStr = args[pIdx + 1]
            if pStr == "quick" { profile = .quick }
            else if pStr == "readonly" { profile = .readOnly }
        }
        
        var size: UInt64 = 1073741824
        var sizeStr = "1 GiB"
        let sIdx = args.firstIndex(of: "--size") ?? -1
        if sIdx >= 0, sIdx + 1 < args.count {
            let sStr = args[sIdx + 1]
            if sStr == "256M" { size = 268435456; sizeStr = "256 MiB" }
            else if sStr == "4G" { size = 4294967296; sizeStr = "4 GiB" }
        }
        
        var targetPath = "/System/Volumes/Data"
        for arg in args {
            if !arg.hasPrefix("--") && arg != "bench" {
                let idx = args.firstIndex(of: arg) ?? -1
                if idx != pIdx + 1 && idx != sIdx + 1 {
                    targetPath = arg
                    break
                }
            }
        }
        
        let targets = BenchTargetResolver.resolveTargets(volumes: volumes, disks: disks, fileSize: size)
        guard let target = targets.first(where: { $0.volume.mountPoint == targetPath || ($0.volume.mountPoint == "/" && targetPath == "/System/Volumes/Data") }) else {
            print("Volume not found, or it can't be tested: \(targetPath). Use --list-targets to check.")
            exit(1)
        }
        
        if let reason = target.rejectionReason {
            print("This volume can't be tested: \(reason)")
            exit(1)
        }
        
        guard let bsd = target.volume.physicalDiskBSDNames.first, let disk = disks.first(where: { $0.bsdName == bsd }) else {
            print("Couldn't find the physical disk.")
            exit(1)
        }
        
        let maxWrites = BenchMath.maxBytesWritten(fileSize: size, profile: profile)
        if !args.contains("--json") {
            print("Will write at most: \(Formatters.bytes(maxWrites))\n")
        }
        
        let runner = BenchmarkRunner(target: target, profile: profile, fileSize: size, physicalDisk: disk, appVersion: DiskProbeInfo.version)
        
        let handler = BenchHandler(profile: profile, sizeStr: sizeStr, isJSON: args.contains("--json"))
        runner.delegate = handler
        
        signal(SIGINT, SIG_IGN)
        let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigSource.setEventHandler {
            print("\nCancelling…")
            runner.cancel()
        }
        sigSource.resume()
        
        runner.start()
        RunLoop.main.run()
    }
}

class BenchHandler: BenchmarkRunnerDelegate {
    let profile: BenchProfile
    let sizeStr: String
    let isJSON: Bool
    
    var lastPrintedProg = -1
    
    init(profile: BenchProfile, sizeStr: String, isJSON: Bool) {
        self.profile = profile
        self.sizeStr = sizeStr
        self.isJSON = isJSON
    }
    
    func benchmarkDidUpdateState(_ state: BenchmarkState) {
        if isJSON { return }
        
        switch state {
        case .preparing(let p):
            let perc = Int(p * 100)
            if perc != lastPrintedProg {
                print("\rPreparing the test file… \(perc)%", terminator: "")
                fflush(stdout)
                lastPrintedProg = perc
            }
        case .pass(let specId, let direction, let pass, let tot, let prog, let speed):
            let label = BenchTestSpec.defaultGrid.first { $0.id == specId }?.label ?? specId
            let dir = direction == .read ? "read" : "write"
            let p = Int(prog * 100)
            print("\rTest: \(label) \(dir) | Pass \(pass)/\(tot) | \(p)% | \(Formatters.speed(speed ?? 0))       ", terminator: "")
            fflush(stdout)
        case .paused(let rem):
            let remStr = String(format: "%.1f", rem)
            print("\rPaused… \(remStr) s left       ", terminator: "")
            fflush(stdout)
        default:
            break
        }
    }
    
    func benchmarkDidFinish(result: BenchmarkResult) {
        if !isJSON {
            print("\n")
        }
        
        if isJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? encoder.encode(result), let s = String(data: d, encoding: .utf8) {
                print(s)
            }
        } else {
            print("Aman Disk \(result.appVersion) — Performance test")
            let profName = profile == .quick ? "Quick (3 passes)" : (profile == .readOnly ? "Read-only (5 passes)" : "Standard (5 passes)")
            print("Volume: \(result.conditions.volumeName) (\(result.conditions.fileSystem)) · File: \(sizeStr) · Profile: \(profName)")
            print("")
            print("                 Read            Write")
            
            for spec in BenchTestSpec.defaultGrid {
                let patStr = spec.pattern == .sequential ? "SEQ" : "RND"
                let blkStr = spec.blockSize >= 1048576 ? "\(spec.blockSize/1048576)M" : "\(spec.blockSize/1024)K"
                let rId = "\(patStr) \(blkStr) QD\(spec.queueDepth)"
                
                var rStr = "—"
                var wStr = "—"
                var lats = ""
                
                if let readRes = result.tests.first(where: { $0.spec == spec && $0.direction == .read }) {
                    let maxMBps = readRes.passes.isEmpty ? 0 : BenchMath.megabytesPerSecond(bytes: BenchMath.best(readRes.passes)!.bytes, seconds: BenchMath.best(readRes.passes)!.seconds)
                    if maxMBps > 0 { rStr = Formatters.speed(maxMBps) }
                    
                    if spec.recordsLatency && spec.queueDepth == 1 {
                        if let p50 = readRes.latencyP50Micros, let p99 = readRes.latencyP99Micros {
                            lats = "      (median latency \(Formatters.integer(UInt64(p50))) µs · 99th percentile \(Formatters.integer(UInt64(p99))) µs)"
                        }
                    }
                }
                
                if let writeRes = result.tests.first(where: { $0.spec == spec && $0.direction == .write }) {
                    let maxMBps = writeRes.passes.isEmpty ? 0 : BenchMath.megabytesPerSecond(bytes: BenchMath.best(writeRes.passes)!.bytes, seconds: BenchMath.best(writeRes.passes)!.seconds)
                    if maxMBps > 0 { wStr = Formatters.speed(maxMBps) }
                }
                
                let rIdPadded = rId.padding(toLength: 14, withPad: " ", startingAt: 0)
                let rStrPadded = rStr.padding(toLength: 15, withPad: " ", startingAt: 0)
                let wStrPadded = wStr.padding(toLength: 15, withPad: " ", startingAt: 0)
                print("\(rIdPadded) \(rStrPadded) \(wStrPadded)\(lats)")
            }
            
            let tempStr: String
            if let tStart = result.conditions.temperatureStartC {
                let tMax = result.conditions.temperatureMaxC ?? tStart
                tempStr = "\(tStart) → \(tMax) °C"
            } else {
                tempStr = "Unknown"
            }
            
            let pwr = result.conditions.onBattery == true ? "battery" : "power adapter"
            print("\nTemperature: \(tempStr) · Written: \(Formatters.bytes(result.conditions.bytesWritten)) · Power: \(pwr)")
            
            if !result.completed {
                let r = result.stopReason ?? "unknown"
                print("\n[!] Test stopped: \(r)")
            }
        }
        
        exit(result.completed ? 0 : 1)
    }
}

enum DiskProbeInfo {
    /// Same version as the app (see build_app.sh).
    static let version = "0.9.2"
}
