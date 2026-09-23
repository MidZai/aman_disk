import Foundation
import DiskHealthCore
import BenchmarkCore

enum BenchCLI {
    static func run(args: [String]) {
        let volumes = VolumeDiscovery.listVolumes()
        let disks = DiskDiscovery.listPhysicalDisks()
        
        BenchCleanup.run(volumes: volumes)
        
        if args.contains("--list-targets") {
            let targets = BenchTargetResolver.resolveTargets(volumes: volumes, disks: disks)
            for target in targets {
                if let reason = target.rejectionReason {
                    var rStr = ""
                    switch reason {
                    case .readOnly: rStr = "Lecture seule"
                    case .network: rStr = "Réseau"
                    case .diskImage: rStr = "Image disque"
                    case .timeMachine: rStr = "Sauvegarde Time Machine"
                    case .accessDenied: rStr = "Accès refusé"
                    case .insufficientFreeSpace(let v): rStr = "Espace insuffisant (\(v))"
                    }
                    print("\(target.volume.mountPoint) : NON (\(rStr))")
                } else {
                    print("\(target.volume.mountPoint) : OUI")
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
        var sizeStr = "1 Gio"
        let sIdx = args.firstIndex(of: "--size") ?? -1
        if sIdx >= 0, sIdx + 1 < args.count {
            let sStr = args[sIdx + 1]
            if sStr == "256M" { size = 268435456; sizeStr = "256 Mio" }
            else if sStr == "4G" { size = 4294967296; sizeStr = "4 Gio" }
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
            print("Volume non trouvé ou test impossible sur \(targetPath). Utilisez --list-targets pour vérifier.")
            exit(1)
        }
        
        if let reason = target.rejectionReason {
            print("Test impossible sur ce volume : \(reason)")
            exit(1)
        }
        
        guard let bsd = target.volume.physicalDiskBSDNames.first, let disk = disks.first(where: { $0.bsdName == bsd }) else {
            print("Impossible de trouver le disque physique.")
            exit(1)
        }
        
        let maxWrites = size * UInt64(1 + (profile.includesWrites ? profile.passes * 4 : 0))
        let maxWritesGB = Double(maxWrites) / 1073741824.0
        if !args.contains("--json") {
            print(String(format: "Écrira au plus : %.1f Gio\n", maxWritesGB))
        }
        
        let runner = BenchmarkRunner(target: target, profile: profile, fileSize: size, physicalDisk: disk)
        
        let handler = BenchHandler(profile: profile, sizeStr: sizeStr, isJSON: args.contains("--json"))
        runner.delegate = handler
        
        signal(SIGINT, SIG_IGN)
        let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigSource.setEventHandler {
            print("\nAnnulation...")
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
                print("\rPréparation du fichier... \(perc)%", terminator: "")
                fflush(stdout)
                lastPrintedProg = perc
            }
        case .pass(let id, let pass, let tot, let prog, let speed):
            let spd = speed ?? 0
            let p = Int(prog * 100)
            let spdStr = String(format: "%.1f", spd)
            print("\rTest : \(id) | Passe \(pass)/\(tot) | \(p)% | \(spdStr) Mo/s       ", terminator: "")
            fflush(stdout)
        case .paused(let rem):
            let remStr = String(format: "%.1f", rem)
            print("\rPause... \(remStr)s restantes       ", terminator: "")
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
            print("Aman Disk 0.9.0 — Test de performances")
            let profName = profile == .quick ? "Rapide (3 passes)" : (profile == .readOnly ? "Lecture seule (5 passes)" : "Standard (5 passes)")
            print("Volume : \(result.conditions.volumeName) (\(result.conditions.fileSystem)) · Fichier : \(sizeStr) · Profil : \(profName)")
            print("")
            print("                 Lecture         Écriture")
            
            for spec in BenchTestSpec.defaultGrid {
                let patStr = spec.pattern == .sequential ? "SEQ" : "RND"
                let blkStr = spec.blockSize >= 1048576 ? "\(spec.blockSize/1048576)M" : "\(spec.blockSize/1024)K"
                let rId = "\(patStr) \(blkStr) QD\(spec.queueDepth)"
                
                var rStr = "—"
                var wStr = "—"
                var lats = ""
                
                if let readRes = result.tests.first(where: { $0.spec == spec && $0.direction == .read }) {
                    let maxMBps = readRes.passes.isEmpty ? 0 : BenchMath.megabytesPerSecond(bytes: BenchMath.best(readRes.passes)!.bytes, seconds: BenchMath.best(readRes.passes)!.seconds)
                    if maxMBps > 0 { rStr = String(format: "%.1f Mo/s", maxMBps) }
                    
                    if spec.recordsLatency && spec.queueDepth == 1 {
                        if let p50 = readRes.latencyP50Micros, let p99 = readRes.latencyP99Micros {
                            lats = "      (latence p50 \(p50) µs · p99 \(p99) µs)"
                        }
                    }
                }
                
                if let writeRes = result.tests.first(where: { $0.spec == spec && $0.direction == .write }) {
                    let maxMBps = writeRes.passes.isEmpty ? 0 : BenchMath.megabytesPerSecond(bytes: BenchMath.best(writeRes.passes)!.bytes, seconds: BenchMath.best(writeRes.passes)!.seconds)
                    if maxMBps > 0 { wStr = String(format: "%.1f Mo/s", maxMBps) }
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
                tempStr = "Inconnue"
            }
            
            let writtenGB = Double(result.conditions.bytesWritten) / 1073741824.0
            let pwr = result.conditions.onBattery == true ? "batterie" : "secteur"
            
            let wrStr = String(format: "%.1f", writtenGB)
            print("\nTempérature : \(tempStr) · Écrit : \(wrStr) Gio · Alimentation : \(pwr)")
            
            if !result.completed {
                let r = result.stopReason ?? "inconnu"
                print("\n[!] Test interrompu : \(r)")
            }
        }
        
        exit(result.completed ? 0 : 1)
    }
}
