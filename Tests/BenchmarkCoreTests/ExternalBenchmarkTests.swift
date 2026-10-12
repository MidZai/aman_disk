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

// Review fixes: an I/O error on a volume that is still mounted is not a disconnection.
extension ExternalBenchmarkTests {
    @Test func ioErrorWithMountPointPresentIsNotADisconnection() {
        #expect(BenchmarkRunner.stopReason(forErrorCode: 5 /* EIO */, mountPointExists: true) == "ioError")
        #expect(BenchmarkRunner.stopReason(forErrorCode: 5 /* EIO */, mountPointExists: false) == "disconnected")
        #expect(BenchmarkRunner.stopReason(forErrorCode: 6 /* ENXIO */, mountPointExists: true) == "disconnected")
        #expect(BenchmarkRunner.stopReason(forErrorCode: 28 /* ENOSPC */, mountPointExists: true) == "error:28")
        #expect(BenchmarkRunner.stopReason(forErrorCode: -100, mountPointExists: true) == nil)
    }
}

// Review fixes: cleanup never touches a file another instance may still be using.
extension ExternalBenchmarkTests {
    @Test func leftoverCleanupOnlyRemovesPathsThatLookLikeTestFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_inflight_\(UUID().uuidString)")
        let testFolder = dir.appendingPathComponent("DiskHealthBench.noindex")
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let genuine = testFolder.appendingPathComponent("DiskHealthBench-\(UUID().uuidString).tmp")
        let stranger = dir.appendingPathComponent("important.txt")
        let misplaced = dir.appendingPathComponent("DiskHealthBench-\(UUID().uuidString).tmp")
        for url in [genuine, stranger, misplaced] { try Data("x".utf8).write(to: url) }

        let inflight = dir.appendingPathComponent("bench-inflight.json")
        try JSONEncoder().encode([genuine.path, stranger.path, misplaced.path]).write(to: inflight)
        BenchInflight.fileURL = inflight
        BenchInflight.cleanUpLeftovers()

        #expect(!FileManager.default.fileExists(atPath: genuine.path))
        #expect(FileManager.default.fileExists(atPath: stranger.path))
        #expect(FileManager.default.fileExists(atPath: misplaced.path), "outside a DiskHealthBench.noindex folder: not ours to delete")
        #expect(!FileManager.default.fileExists(atPath: inflight.path))
    }

    @Test func cleanupKeepsAFileModifiedLessThanTwoMinutesAgo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench_cleanup_\(UUID().uuidString)")
        let testFolder = dir.appendingPathComponent("DiskHealthBench.noindex")
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fresh = testFolder.appendingPathComponent("DiskHealthBench-fresh.tmp")
        let stale = testFolder.appendingPathComponent("DiskHealthBench-stale.tmp")
        for url in [fresh, stale] { try Data("x".utf8).write(to: url) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 60)], ofItemAtPath: stale.path)

        BenchCleanup.run(volumes: [Volume(bsdName: "disk9s1", name: "Scratch", mountPoint: dir.path, format: "APFS",
                                          totalBytes: 1, availableBytes: 1, physicalDiskBSDNames: ["disk9"])])
        #expect(FileManager.default.fileExists(atPath: fresh.path), "another instance may be using it")
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: testFolder.path), "not empty, so kept")
    }
}
