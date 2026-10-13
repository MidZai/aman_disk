import Testing
import Foundation
@testable import DiskHealthCore

/// The extra tables once held French in the Hindi and Vietnamese tables, and Portuguese in the
/// Spanish one: each table must be written in its own language.
@Suite struct ExtraTranslationsLanguageTests {
    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @Test func hindiIsWrittenInDevanagari() {
        // Short technical values (GB, MB/s, TB, kB…) stay in Latin letters.
        let wrong = ExtraTranslations.hindi.filter { key, value in
            !value.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) } && value.count > 4 && value != key
        }
        #expect(wrong.isEmpty, "Hindi values without Devanagari: \(wrong.keys.sorted().prefix(5))")
    }

    @Test func vietnameseHasNoFrench() {
        let french = "\\b(les|des|une|est|pour|votre|vos|données|disque|aucun|mesure)\\b"
        let wrong = ExtraTranslations.vietnamese.filter { _, value in matches(value, french) }
        #expect(wrong.isEmpty, "French in the Vietnamese table: \(wrong.keys.sorted().prefix(5))")
    }

    @Test func spanishHasNoPortuguese() {
        let portuguese = "ção|ções|ões|\\b(não|você|seus?|unidads|desconhecida|arquivo|gravad[ao]|está em)\\b"
        let wrong = ExtraTranslations.spanish.filter { _, value in matches(value, portuguese) }
        #expect(wrong.isEmpty, "Portuguese in the Spanish table: \(wrong.keys.sorted().prefix(5))")
    }
}
