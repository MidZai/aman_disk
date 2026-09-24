import Testing
import Foundation
@testable import DiskHealthCore

/// Fake ATA drive: no command is sent to a real drive.
private final class SimulatedATADevice: ATASmartDevice {
    var smartEnabled: Bool
    var enableError: ATAReadError?
    private(set) var enableCalls = 0
    let serial = "SIM-0001"

    init(smartEnabled: Bool, enableError: ATAReadError? = nil) {
        self.smartEnabled = smartEnabled
        self.enableError = enableError
    }

    func read(bsdName: String) throws -> DiskHealthSnapshot {
        guard smartEnabled else { throw ATAReadError.smartDisabled }
        return .ata(ATASmartSnapshot(attributes: [], model: "Simulated SSD", firmware: "1.0", serialNumber: serial, rotationRate: 1, thresholdExceeded: false, checksumValid: true))
    }

    func serialNumber(bsdName: String) -> String? { serial }

    func enableSmart(bsdName: String) throws {
        enableCalls += 1
        if let enableError { throw enableError }
        smartEnabled = true
    }
}

@Suite final class SmartActivationTests {
    private let suiteName = "SmartActivationTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func disabledThenEnabledThenReadsNormally() throws {
        let device = SimulatedATADevice(smartEnabled: false)
        let activator = SmartActivator(device: device, memory: UserDefaultsActivationMemory(defaults: defaults))

        guard case .enabled(let snapshot) = try activator.read(bsdName: "disk2", autoEnable: true) else {
            Issue.record("S.M.A.R.T. should have been turned on")
            return
        }
        #expect(device.enableCalls == 1)
        #expect(snapshot == (try device.read(bsdName: "disk2")))

        // Later reads: S.M.A.R.T. is on, no more commands are sent.
        guard case .read = try activator.read(bsdName: "disk2", autoEnable: true) else {
            Issue.record("Lecture normale attendue")
            return
        }
        #expect(device.enableCalls == 1)
    }

    @Test func refusedActivationReportsTheCode() throws {
        let device = SimulatedATADevice(smartEnabled: false, enableError: .ioError(-536870201))
        let activator = SmartActivator(device: device, memory: UserDefaultsActivationMemory(defaults: defaults))

        #expect(try activator.read(bsdName: "disk2", autoEnable: true) == .enableFailed(code: -536870201))
        #expect(device.enableCalls == 1)
    }

    @Test func secondLaunchDoesNotRetry() throws {
        let device = SimulatedATADevice(smartEnabled: false, enableError: .ioError(-536870201))
        _ = try SmartActivator(device: device, memory: UserDefaultsActivationMemory(defaults: defaults))
            .read(bsdName: "disk2", autoEnable: true)

        // New launch: new instance, same preferences, different BSD name.
        let relaunched = SmartActivator(device: device, memory: UserDefaultsActivationMemory(defaults: defaults))
        #expect(try relaunched.read(bsdName: "disk3", autoEnable: true) == .enableFailed(code: -536870201))
        #expect(device.enableCalls == 1)

        // Only a user action (“Try Again”) sends the command again.
        device.enableError = nil
        guard case .enabled = try relaunched.enable(bsdName: "disk3") else {
            Issue.record("The manual retry should have succeeded")
            return
        }
        #expect(device.enableCalls == 2)
    }

    @Test func settingOffNeverSendsTheCommand() throws {
        let device = SimulatedATADevice(smartEnabled: false)
        let activator = SmartActivator(device: device, memory: UserDefaultsActivationMemory(defaults: defaults))

        #expect(try activator.read(bsdName: "disk2", autoEnable: false) == .disabled)
        #expect(device.enableCalls == 0)
    }

    @Test func eventLogKeepsActivation() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        DiskEventLog(baseURL: dir).append(DiskEvent(date: date, kind: .smartEnabled), for: "KEY")

        #expect(DiskEventLog(baseURL: dir).events(for: "KEY") == [DiskEvent(date: date, kind: .smartEnabled)])
        #expect(DiskEventLog(baseURL: dir).events(for: "OTHER").isEmpty)
    }
}
