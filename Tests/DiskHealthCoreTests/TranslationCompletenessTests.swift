import Testing
import Foundation
@testable import DiskHealthCore

@Suite struct TranslationCompletenessTests {

    @Test func allStringKeysExistInEnglish() {
        let en = Translations.english
        for key in StringKey.allCases {
            let val = en[key]
            #expect(val != nil, "Missing English translation for \(key.rawValue)")
            #expect(val?.isEmpty == false, "Empty English translation for \(key.rawValue)")
        }
    }

    @Test func allLanguagesHaveCompleteStringKeys() {
        for lang in AppLanguage.allCases {
            let dict = Translations.dictionary(for: lang)
            for key in StringKey.allCases {
                let val = dict[key]
                #expect(val != nil, "Missing translation for key '\(key.rawValue)' in language '\(lang.rawValue)'")
                #expect(val?.isEmpty == false, "Empty translation for key '\(key.rawValue)' in language '\(lang.rawValue)'")
            }
        }
    }

    @Test func rtlLayoutSupport() {
        #expect(AppLanguage.arabic.isRTL == true)
        for lang in AppLanguage.allCases where lang != .arabic {
            #expect(lang.isRTL == false, "\(lang.rawValue) should not be RTL")
        }
    }

    @Test func brazilianPortugueseConfiguration() {
        #expect(AppLanguage.portuguese.rawValue == "pt-BR")
        #expect(AppLanguage(rawValue: "pt-BR") == .portuguese)
        #expect(AppLanguage(rawValue: "pt") == .portuguese) // Backward compatibility
        #expect(AppLanguage.portuguese.flag == "🇧🇷")
        #expect(AppLanguage.portuguese.locale.identifier == "pt_BR")
        #expect(AppLanguage.portuguese.nativeName == "Português (Brasil)")
    }

    @Test func temperatureUnitConversions() {
        #expect(Formatters.temperature(0, unit: .celsius) == "0\u{00A0}°C")
        #expect(Formatters.temperature(0, unit: .fahrenheit) == "32\u{00A0}°F")
        #expect(Formatters.temperature(25, unit: .celsius) == "25\u{00A0}°C")
        #expect(Formatters.temperature(25, unit: .fahrenheit) == "77\u{00A0}°F")
        #expect(Formatters.temperature(100, unit: .celsius) == "100\u{00A0}°C")
        #expect(Formatters.temperature(100, unit: .fahrenheit) == "212\u{00A0}°F")
    }

    @Test func formattersApproximateDurationPlurals() {
        #expect(Formatters.approximateDuration(hours: 10, language: .english) == "less than a day")
        #expect(Formatters.approximateDuration(hours: 24, language: .english) == "1\u{00A0}day")
        #expect(Formatters.approximateDuration(hours: 48, language: .english) == "2\u{00A0}days")

        #expect(Formatters.approximateDuration(hours: 10, language: .french) == "moins d'un jour")
        #expect(Formatters.approximateDuration(hours: 24, language: .french) == "1\u{00A0}jour")
        #expect(Formatters.approximateDuration(hours: 48, language: .french) == "2\u{00A0}jours")

        let ru24 = Formatters.approximateDuration(hours: 24, language: .russian)
        let ru48 = Formatters.approximateDuration(hours: 48, language: .russian)
        let ru120 = Formatters.approximateDuration(hours: 120, language: .russian)
        #expect(!ru24.isEmpty)
        #expect(!ru48.isEmpty)
        #expect(!ru120.isEmpty)
        #expect(ru24 != ru48)

        let ar24 = Formatters.approximateDuration(hours: 24, language: .arabic)
        let ar48 = Formatters.approximateDuration(hours: 48, language: .arabic)
        let ar120 = Formatters.approximateDuration(hours: 120, language: .arabic)
        #expect(!ar24.isEmpty)
        #expect(!ar48.isEmpty)
        #expect(!ar120.isEmpty)
    }

    @Test func dynamicTranslationFallback() {
        let text = Localization.translate(
            english: "Reading health data failed (code 5). Try again; if the problem persists, export a diagnostic.",
            french: "Échec de lecture des données de santé (code 5). Réessayez ; si le problème persiste, exportez un diagnostic.",
            language: .arabic
        )
        #expect(!text.isEmpty)
        #expect(text.contains("5"))
    }
}
