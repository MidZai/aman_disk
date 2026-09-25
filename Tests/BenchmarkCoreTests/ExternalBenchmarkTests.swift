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
