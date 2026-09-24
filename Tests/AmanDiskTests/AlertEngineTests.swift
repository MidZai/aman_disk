import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Alerts, tested with a fake clock and a fake notification poster.
@Suite struct AlertEngineTests {
    init() { Localization.language = .english }

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
}
