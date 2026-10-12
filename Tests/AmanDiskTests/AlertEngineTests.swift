import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Alerts, tested with a fake clock and a fake notification poster.
@Suite struct AlertEngineTests {
    // Only writes when needed: scripts/test.sh already starts in English, and a write
    // while other suites run in parallel races on the shared formatter cache.
    init() { if Localization.language != .english { Localization.language = .english } }

    final class FakePoster: NotificationPosting {
        var posted: [AlertEvent] = []
        func post(_ event: AlertEvent) { posted.append(event) }
    }
    
    final class FakeClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }
    
    let poster = FakePoster()
    let clock = FakeClock()
    
    func makeEngine() -> AlertEngine {
        let c = clock
        return AlertEngine(poster: poster, clock: { c.now })
    }
    
    func reading(status: HealthStatus = .good, reason: String? = nil, temp: Int? = 40, rotational: Bool = false, life: Int? = 90) -> AlertReading {
        AlertReading(diskId: "disk0", name: "APPLE SSD", status: status, firstReason: reason, temperatureC: temp, isRotational: rotational, lifePercent: life)
    }
    
    /// One reading every 30 s for `seconds`.
    func feed(_ engine: AlertEngine, _ r: AlertReading, for seconds: TimeInterval) {
        var t: TimeInterval = 0
        while t <= seconds {
            engine.process([r])
            clock.advance(30)
            t += 30
        }
    }
    
    @Test func firstReadingIsABaselineWithoutAlert() {
        let engine = makeEngine()
        engine.process([reading(status: .bad, reason: "3 pending sectors", life: 20)])
        #expect(poster.posted.isEmpty)
    }
    
    @Test func statusChangeIsNotifiedOnce() {
        let engine = makeEngine()
        engine.process([reading()])
        engine.process([reading(status: .caution, reason: "3 pending sectors")])
        engine.process([reading(status: .caution, reason: "3 pending sectors")])
        #expect(poster.posted.map(\.message) == ["APPLE SSD: Needs attention. 3 pending sectors."])
        
        engine.process([reading(status: .bad, reason: "Spare exhausted.")])
        #expect(poster.posted.count == 2)
        #expect(poster.posted.last?.message == "APPLE SSD: Likely failing. Spare exhausted.")
        #expect(poster.posted.last?.diskId == "disk0")
        
        // Back to “good”: no notification.
        engine.process([reading(status: .good)])
        #expect(poster.posted.count == 2)
    }
    
    @Test func ssdOverheatAfterFiveMinutesThenRearmsBelowThresholdMinus5() {
        let engine = makeEngine()
        feed(engine, reading(temp: 61), for: 4 * 60)
        #expect(poster.posted.isEmpty) // only 4 min
        feed(engine, reading(temp: 61), for: 60)
        #expect(poster.posted.map(\.message) == ["APPLE SSD is running hot: 61 °C for 5 minutes."])
        
        // Stays hot: no repeat.
        feed(engine, reading(temp: 62), for: 20 * 60)
        #expect(poster.posted.count == 1)
        
        // Drops to 57 °C (not below 55), then rises again: still no new alert.
        feed(engine, reading(temp: 57), for: 60)
        feed(engine, reading(temp: 61), for: 10 * 60)
        #expect(poster.posted.count == 1)
        
        // Below 55 °C: rearmed; 5 min above 60 → new alert.
        feed(engine, reading(temp: 54), for: 60)
        feed(engine, reading(temp: 63), for: 5 * 60)
        #expect(poster.posted.count == 2)
    }
    
    @Test func dipBelowThresholdRestartsTheFiveMinutes() {
        let engine = makeEngine()
        feed(engine, reading(temp: 61), for: 4 * 60)
        feed(engine, reading(temp: 59), for: 0)
        feed(engine, reading(temp: 61), for: 4 * 60)
        #expect(poster.posted.isEmpty)
    }
    
    @Test func hardDiskThresholdIs55() {
        let engine = makeEngine()
        feed(engine, reading(temp: 56, rotational: true), for: 5 * 60)
        #expect(poster.posted.map(\.kind) == [.overheat])
    }
    
    @Test func gapInReadingsRestartsOverheatTimer() {
        let engine = makeEngine()
        feed(engine, reading(temp: 61), for: 3 * 60)
        clock.advance(3600) // app closed
        feed(engine, reading(temp: 61), for: 3 * 60)
        #expect(poster.posted.isEmpty)
    }
    
    @Test func lifeThresholdsAreNotifiedOnceEach() {
        let engine = makeEngine()
        engine.process([reading(life: 52)])
        engine.process([reading(life: 50)])
        engine.process([reading(life: 49)])
        engine.process([reading(life: 26)])
        engine.process([reading(life: 25)])
        engine.process([reading(life: 10)])
        engine.process([reading(life: 9)])
        #expect(poster.posted.map(\.kind) == [.lifeThreshold(50), .lifeThreshold(25), .lifeThreshold(10)])
        #expect(poster.posted.first?.message == "APPLE SSD: remaining life dropped below 50% (50%).")
    }
    
    @Test func jumpOverSeveralThresholdsGivesOneNotification() {
        let engine = makeEngine()
        engine.process([reading(life: 60)])
        engine.process([reading(life: 20)])
        engine.process([reading(life: 15)])
        #expect(poster.posted.map(\.kind) == [.lifeThreshold(25)])
    }
    
    @Test func disabledEngineTracksStateButPostsNothing() {
        let engine = makeEngine()
        engine.isEnabled = false
        engine.process([reading()])
        engine.process([reading(status: .caution)])
        #expect(poster.posted.isEmpty)
        // When turned on, the earlier change isn't sent again.
        engine.isEnabled = true
        engine.process([reading(status: .caution)])
        #expect(poster.posted.isEmpty)
    }
    
    @Test func stateSurvivesARestart() throws {
        let engine = makeEngine()
        engine.process([reading(status: .caution, life: 40)])
        let data = try JSONEncoder().encode(engine.states)
        let restored = try JSONDecoder().decode([String: AlertEngine.DiskState].self, from: data)
        let c = clock
        let engine2 = AlertEngine(poster: poster, clock: { c.now }, states: restored)
        engine2.process([reading(status: .caution, life: 40)])
        #expect(poster.posted.isEmpty)
    }

    @Test func externalDriveReceivesAlerts() {
        let engine = makeEngine()
        let ext = AlertReading(diskId: "disk3", name: "Crucial X8", status: .good, firstReason: nil, temperatureC: 35, isRotational: false, lifePercent: 80)
        engine.process([ext])
        #expect(poster.posted.isEmpty)

        // Status degraded to caution
        let degraded = AlertReading(diskId: "disk3", name: "Crucial X8", status: .caution, firstReason: "Overheating wear", temperatureC: 38, isRotational: false, lifePercent: 80)
        engine.process([degraded])
        #expect(poster.posted.count == 1)
        #expect(poster.posted.last?.diskId == "disk3")
        #expect(poster.posted.last?.message == "Crucial X8: Needs attention. Overheating wear.")
    }

    @Test func externalDriveHotUnplugEmitsNoAlert() {
        let engine = makeEngine()
        let internalDisk = AlertReading(diskId: "disk0", name: "Internal SSD", status: .good, firstReason: nil, temperatureC: 35, isRotational: false, lifePercent: 95)
        let externalDisk = AlertReading(diskId: "disk3", name: "Seagate Backup", status: .good, firstReason: nil, temperatureC: 32, isRotational: true, lifePercent: nil)

        // Both drives connected
        engine.process([internalDisk, externalDisk])
        #expect(poster.posted.isEmpty)

        // Advance clock and simulate external drive hot-unplug: only internalDisk is reported
        clock.advance(30)
        let postDisconnectEvents = engine.process([internalDisk])

        // Verify: ZERO alerts emitted when external drive is unplugged
        #expect(postDisconnectEvents.isEmpty)
        #expect(poster.posted.isEmpty)

        // Another cycle without external drive
        clock.advance(30)
        let secondCycleEvents = engine.process([internalDisk])
        #expect(secondCycleEvents.isEmpty)
        #expect(poster.posted.isEmpty)
    }
}

// Review fixes: alert state is keyed by the drive's identity, never by its BSD name.
extension AlertEngineTests {
    private func disk(serial: String, life: Int) -> RealDisk {
        let physical = PhysicalDisk(bsdName: "disk4", model: "Crucial X8", sizeBytes: 1_000_000_000_000, isInternal: false,
                                    connection: .usb, driveConnection: .usb, volumeNames: ["X8"], protocolType: .usb,
                                    mediumType: .solidState, healthCapability: .supported, serialNumber: serial)
        let log = NVMeSmartLog(criticalWarning: 0, compositeTemperatureKelvin: 310, availableSpare: 100, availableSpareThreshold: 10,
                               percentageUsed: UInt8(100 - life), dataUnitsRead: 1, dataUnitsWritten: 1, hostReadCommands: 0,
                               hostWriteCommands: 0, controllerBusyTimeMinutes: 0, powerCycles: 10, powerOnHours: 100,
                               unsafeShutdowns: 0, mediaErrors: 0, errorLogEntries: 0)
        let identify = NVMeIdentify(serialNumber: serial, modelNumber: "Crucial X8", firmwareRevision: "1.0",
                                    warningTempKelvin: 0, criticalTempKelvin: 0, totalCapacityBytes: 1_000_000_000_000)
        let snapshot = DiskHealthSnapshot.nvme(log, identify)
        return RealDisk(physical: physical, snapshot: snapshot, health: AppManager.evaluate(snapshot))
    }

    @Test func twoDrivesUnderTheSameBSDNameShareNoAlertState() {
        let engine = makeEngine()
        let first = LiveStatusController.alertReadings(for: [disk(serial: "AAAA1111", life: 90)])
        let second = LiveStatusController.alertReadings(for: [disk(serial: "BBBB2222", life: 40)])
        #expect(first.map(\.diskId) != second.map(\.diskId))
        #expect(first.first?.diskId != "disk4")

        engine.process(first)
        engine.process(second)
        #expect(poster.posted.isEmpty, "the second drive is a baseline, not a drop from 90% to 40%")
        #expect(engine.states.count == 2)
    }
}
