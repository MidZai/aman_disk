import Testing
import Foundation
@testable import BenchmarkCore
import DiskHealthCore

@Suite struct ExternalBenchmarkTests {

    @Test func testUnmountedVolumeIsRejected() {
        let unmountedVolume = Volume(
            bsdName: "disk5s1",
            name: "Unmounted External",
            mountPoint: "",
            format: "APFS",
            totalBytes: 500_000_000_000,
            availableBytes: 0,
            physicalDiskBSDNames: ["disk5"]
        )
        let nonExistentVolume = Volume(
            bsdName: "disk5s2",
            name: "Vanished Volume",
            mountPoint: "/Volumes/NonExistent_XYZ_12345",
            format: "ExFAT",
            totalBytes: 500_000_000_000,
            availableBytes: 0,
            physicalDiskBSDNames: ["disk5"]
        )
        let physical = PhysicalDisk(
            bsdName: "disk5",
            model: "External USB SSD",
            sizeBytes: 500_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Unmounted External", "Vanished Volume"],
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )

        let targets = BenchTargetResolver.resolveTargets(volumes: [unmountedVolume, nonExistentVolume], disks: [physical])
        #expect(targets.count == 2)
        #expect(targets[0].rejectionReason == .unmounted)
        #expect(targets[1].rejectionReason == .unmounted)
        #expect(targets[0].rejectionReason?.description == L("Unmounted", "Non monté"))
    }

    @Test func testDisconnectionDuringBenchmarkCleansUpAndReportsReason() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_disconnect_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let volume = Volume(
            bsdName: "disk8s1",
            name: "Test Volume",
            mountPoint: tempDir.path,
            format: "APFS",
            totalBytes: 100_000_000_000,
            availableBytes: 50_000_000_000,
            physicalDiskBSDNames: ["disk8"]
        )
        let physical = PhysicalDisk(
            bsdName: "disk8",
            model: "SanDisk Extreme",
            sizeBytes: 100_000_000_000,
            isInternal: false,
            connection: .usb,
            driveConnection: .usb,
            volumeNames: ["Test Volume"],
            usbLinkSpeedBps: 10_000_000_000,
            protocolType: .usb,
            mediumType: .solidState,
            healthCapability: .unsupported(reason: .usbBridge)
        )

        let target = BenchTarget(
            volume: volume,
            testDirectoryURL: tempDir,
            rejectionReason: nil,
            availableBytes: 50_000_000_000,
            isEncrypted: false,
            fileSystem: "APFS"
        )

        // Single pass 1MB test
        let spec = BenchTestSpec(id: "TEST_SEQ", label: "TEST", pattern: .sequential, blockSize: 65536, queueDepth: 1, recordsLatency: false)
        let runner = BenchmarkRunner(
            target: target,
            profile: .quick,
            fileSize: 1_048_576,
            physicalDisk: physical,
            specGrid: [spec]
        )

        final class TestDelegate: BenchmarkRunnerDelegate, @unchecked Sendable {
            var finishedResult: BenchmarkResult?
            let sema = DispatchSemaphore(value: 0)

            func benchmarkDidUpdateState(_ state: BenchmarkState) {}
            func benchmarkDidComplete(test: TestResult) {}
            func benchmarkDidFinish(result: BenchmarkResult) {
                finishedResult = result
                sema.signal()
            }
        }

        let delegate = TestDelegate()
        runner.delegate = delegate
        runner.start()

        // Simulate drive disconnection mid-test
        runner.stopForDisconnection()
        delegate.sema.wait()

        let result = delegate.finishedResult
        #expect(result != nil)
        #expect(result?.completed == false)
        #expect(result?.stopReason == "disconnected")

        // Verify test file was deleted
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        let benchFiles = files.filter { $0.hasPrefix("DiskHealthBench-") && $0.hasSuffix(".tmp") }
        #expect(benchFiles.isEmpty)
    }
}

// Review fixes: nothing is written on a volume before the user starts a test, nothing is left after.
extension ExternalBenchmarkTests {
    private static func volume(at dir: URL) -> Volume {
        Volume(bsdName: "disk9s1", name: "Scratch", mountPoint: dir.path, format: "APFS",
               totalBytes: 100_000_000_000, availableBytes: 50_000_000_000, physicalDiskBSDNames: ["disk9"])
    }

    private static func physical() -> PhysicalDisk {
        PhysicalDisk(bsdName: "disk9", model: "Scratch SSD", sizeBytes: 100_000_000_000, isInternal: false,
                     connection: .usb, driveConnection: .usb, volumeNames: ["Scratch"], protocolType: .usb,
                     mediumType: .solidState, healthCapability: .unsupported(reason: .usbBridge))
    }

    @Test func resolvingTargetsWritesNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_resolve_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let targets = BenchTargetResolver.resolveTargets(volumes: [Self.volume(at: dir)], disks: [Self.physical()], fileSize: 1_048_576)
        #expect(targets.count == 1)
        #expect(targets[0].rejectionReason == nil)
        #expect(targets[0].testDirectoryURL.path == dir.appendingPathComponent("DiskHealthBench.noindex").path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func readOnlyLocationIsRejectedWithoutWriting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_ro_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        let targets = BenchTargetResolver.resolveTargets(volumes: [Self.volume(at: dir)], disks: [Self.physical()], fileSize: 1_048_576)
        #expect(targets[0].rejectionReason == .accessDenied)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func completedTestLeavesNothingBehind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_clean_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = BenchTarget(volume: Self.volume(at: dir), testDirectoryURL: dir.appendingPathComponent("DiskHealthBench.noindex"),
                                 rejectionReason: nil, availableBytes: 50_000_000_000, isEncrypted: false, fileSystem: "APFS")
        let spec = BenchTestSpec(id: "TEST_SEQ", label: "TEST", pattern: .sequential, blockSize: 65536, queueDepth: 1, recordsLatency: false)
        let runner = BenchmarkRunner(target: target, profile: .quick, fileSize: 1_048_576, physicalDisk: Self.physical(), specGrid: [spec])

        final class Waiter: BenchmarkRunnerDelegate, @unchecked Sendable {
            var result: BenchmarkResult?
            let sema = DispatchSemaphore(value: 0)
            func benchmarkDidUpdateState(_ state: BenchmarkState) {}
            func benchmarkDidFinish(result: BenchmarkResult) { self.result = result; sema.signal() }
        }
        let waiter = Waiter()
        runner.delegate = waiter
        runner.start()
        waiter.sema.wait()

        #expect(waiter.result?.completed == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty, "test folder must be removed when empty")
    }
}
