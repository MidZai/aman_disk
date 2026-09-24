import Foundation

/// Interface language. English by default; French stays available in Settings.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case french = "fr"

    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .french: return Locale(identifier: "fr_FR")
        }
    }

    /// Name of the language, written in that language.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        }
    }
}

/// The language is read once at launch: a change in Settings takes effect after a relaunch,
/// so cached texts (catalogs, menus) never mix two languages.
public enum Localization {
    public static let defaultsKey = "appLanguage"

    public static var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .english {
        didSet { Formatters.locale = language.locale }
    }

    public static var isFrench: Bool { language == .french }
}

/// Picks the text for the current language: `L("Read", "Lecture")`.
public func L(_ english: String, _ french: String) -> String {
    Localization.isFrench ? french : english
}
