import Foundation
import Testing
@testable import DiskHealthApp
import DiskHealthCore

/// Phase 5 (0.9) : alertes testées avec une horloge et un fournisseur de notifications simulés.
@Suite struct AlertEngineTests {
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
    
    /// Relevés toutes les 30 s pendant `seconds`.
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
        engine.process([reading(status: .bad, reason: "3 secteurs en attente", life: 20)])
        #expect(poster.posted.isEmpty)
    }
    
    @Test func statusChangeIsNotifiedOnce() {
        let engine = makeEngine()
        engine.process([reading()])
        engine.process([reading(status: .caution, reason: "3 secteurs en attente")])
        engine.process([reading(status: .caution, reason: "3 secteurs en attente")])
        #expect(poster.posted.map(\.message) == ["APPLE SSD : À surveiller. 3 secteurs en attente."])
        
        engine.process([reading(status: .bad, reason: "Réserve épuisée.")])
        #expect(poster.posted.count == 2)
        #expect(poster.posted.last?.message == "APPLE SSD : Défaillance probable. Réserve épuisée.")
        #expect(poster.posted.last?.diskId == "disk0")
        
        // Retour à « bon » : pas de notification.
        engine.process([reading(status: .good)])
        #expect(poster.posted.count == 2)
    }
    
    @Test func ssdOverheatAfterFiveMinutesThenRearmsBelowThresholdMinus5() {
        let engine = makeEngine()
        feed(engine, reading(temp: 61), for: 4 * 60)
        #expect(poster.posted.isEmpty) // 4 min seulement
        feed(engine, reading(temp: 61), for: 60)
        #expect(poster.posted.map(\.message) == ["APPLE SSD chauffe : 61 °C depuis 5 minutes."])
        
        // Reste chaud : pas de répétition.
        feed(engine, reading(temp: 62), for: 20 * 60)
        #expect(poster.posted.count == 1)
        
        // Redescend à 57 °C (pas sous 55) puis remonte : toujours pas de nouvelle alerte.
        feed(engine, reading(temp: 57), for: 60)
        feed(engine, reading(temp: 61), for: 10 * 60)
        #expect(poster.posted.count == 1)
        
        // Sous 55 °C : réarmé ; 5 min au-dessus de 60 → nouvelle alerte.
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
        clock.advance(3600) // app fermée
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
        #expect(poster.posted.first?.message == "APPLE SSD : durée de vie restante passée sous 50 % (50 %).")
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
        // À l'activation, l'ancien changement n'est pas renvoyé.
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
