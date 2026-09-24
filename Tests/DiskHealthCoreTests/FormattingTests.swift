import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct FormattingTests {
    /// Typographie française : espace fine insécable entre les milliers, espace insécable avant l'unité.
    let thin = "\u{202F}"
    let nbsp = "\u{00A0}"

    // Ces attentes sont en français ; l'anglais est la langue par défaut.
    init() { Localization.language = .french }

    @Test func bytes() {
        #expect(Formatters.bytes(500_300_000_000) == "500,3\(nbsp)Go")
        #expect(Formatters.bytes(48_300_000_000_000) == "48,3\(nbsp)To")
        #expect(Formatters.bytes(2_000_000_000_000) == "2\(nbsp)To")
        #expect(Formatters.bytes(512_000_000_000) == "512\(nbsp)Go")
        #expect(Formatters.bytes(1_500_000_000) == "1,5\(nbsp)Go")
        // 999,96 Go s'arrondit à 1 To, pas à « 1 000 Go ».
        #expect(Formatters.bytes(999_960_000_000) == "1\(nbsp)To")
        #expect(Formatters.bytes(512) == "512\(nbsp)octets")
    }

    @Test func integer() {
        #expect(Formatters.integer(UInt64(1207)) == "1\(thin)207")
        #expect(Formatters.integer(UInt64(0)) == "0")
        #expect(Formatters.integer(2814) == "2\(thin)814")
    }

    @Test func hoursAndTemperature() {
        #expect(Formatters.hours(2814) == "2\(thin)814\(nbsp)h")
        #expect(Formatters.temperature(38) == "38\(nbsp)°C")
    }

    @Test func approximateDuration() {
        #expect(Formatters.approximateDuration(hours: 10) == "moins d'un jour")
        #expect(Formatters.approximateDuration(hours: 24 * 40) == "40\(nbsp)jours")
        #expect(Formatters.approximateDuration(hours: 3440) == "5\(nbsp)mois")
        #expect(Formatters.approximateDuration(hours: 31_482) == "3,6\(nbsp)ans")
    }

    @Test func dataUnitsNeverOverflow() {
        #expect(Formatters.dataUnitsToBytes(2) == 1_024_000)
        #expect(Formatters.dataUnitsToBytes(.max) == .max)
        #expect(UInt64(1 << 48).saturatingMultiplied(by: 1 << 20) == .max)
    }

    @Test func ageLabel() {
        let now = Date()
        #expect(Formatters.age(since: now.addingTimeInterval(-12), now: now) == "il y a 12\(nbsp)s")
        #expect(Formatters.age(since: now.addingTimeInterval(-600), now: now) == "il y a 10\(nbsp)min")
    }
}
