import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct FormattingTests {
    /// No-break space between a number and its unit, so “36 °C” never wraps.
    let nbsp = "\u{00A0}"

    init() { Localization.language = .english }

    @Test func bytes() {
        #expect(Formatters.bytes(500_300_000_000) == "500.3\(nbsp)GB")
        #expect(Formatters.bytes(48_300_000_000_000) == "48.3\(nbsp)TB")
        #expect(Formatters.bytes(2_000_000_000_000) == "2\(nbsp)TB")
        #expect(Formatters.bytes(512_000_000_000) == "512\(nbsp)GB")
        #expect(Formatters.bytes(1_500_000_000) == "1.5\(nbsp)GB")
        // 999.96 GB rounds to 1 TB, not to “1,000 GB”.
        #expect(Formatters.bytes(999_960_000_000) == "1\(nbsp)TB")
        #expect(Formatters.bytes(512) == "512\(nbsp)bytes")
    }

    @Test func integer() {
        #expect(Formatters.integer(UInt64(1207)) == "1,207")
        #expect(Formatters.integer(UInt64(0)) == "0")
        #expect(Formatters.integer(2814) == "2,814")
    }

    @Test func hoursAndTemperature() {
        #expect(Formatters.hours(2814) == "2,814\(nbsp)h")
        #expect(Formatters.temperature(38) == "38\(nbsp)°C")
    }

    @Test func approximateDuration() {
        #expect(Formatters.approximateDuration(hours: 10) == "less than a day")
        #expect(Formatters.approximateDuration(hours: 24 * 40) == "40\(nbsp)days")
        #expect(Formatters.approximateDuration(hours: 3440) == "5\(nbsp)months")
        #expect(Formatters.approximateDuration(hours: 31_482) == "3.6\(nbsp)years")
    }

    @Test func dataUnitsNeverOverflow() {
        #expect(Formatters.dataUnitsToBytes(2) == 1_024_000)
        #expect(Formatters.dataUnitsToBytes(.max) == .max)
        #expect(UInt64(1 << 48).saturatingMultiplied(by: 1 << 20) == .max)
    }

    @Test func ageLabel() {
        let now = Date()
        #expect(Formatters.age(since: now.addingTimeInterval(-12), now: now) == "12\(nbsp)s ago")
        #expect(Formatters.age(since: now.addingTimeInterval(-600), now: now) == "10\(nbsp)min ago")
    }
}
