import Foundation

/// Mise en forme des nombres, tailles, durées et dates.
///
/// Les nombres suivent la langue de l'interface (`Localization.language`), pas celle du système :
/// sinon « 500.3 Go » côtoierait des libellés français, ou « 500,3 GB » des libellés anglais.
///
/// Les formateurs sont créés une seule fois : `NumberFormatter` et `DateFormatter` coûtent cher
/// à instancier, et ces fonctions sont appelées à chaque rendu des vues.
public enum Formatters {
    public static var locale: Locale = Localization.language.locale {
        didSet { cache = Cache(locale: locale) }
    }

    /// Espace insécable entre un nombre et son unité : « 36 °C » ne se coupe jamais en fin de ligne.
    public static let unitSpace = "\u{00A0}"

    private final class Cache {
        let integer: NumberFormatter
        let decimal1: NumberFormatter
        let percent: NumberFormatter
        let dateMedium: DateFormatter
        let dateLong: DateFormatter
        let time: DateFormatter

        init(locale: Locale) {
            func number(fractionDigits: Int) -> NumberFormatter {
                let nf = NumberFormatter()
                nf.locale = locale
                nf.numberStyle = .decimal
                nf.minimumFractionDigits = 0
                nf.maximumFractionDigits = fractionDigits
                nf.roundingMode = .halfUp
                return nf
            }
            integer = number(fractionDigits: 0)
            decimal1 = number(fractionDigits: 1)
            percent = number(fractionDigits: 1)
            dateMedium = DateFormatter()
            dateMedium.locale = locale
            dateMedium.dateStyle = .medium
            dateMedium.timeStyle = .short
            dateLong = DateFormatter()
            dateLong.locale = locale
            dateLong.dateStyle = .long
            dateLong.timeStyle = .short
            time = DateFormatter()
            time.locale = locale
            time.dateStyle = .none
            time.timeStyle = .short
        }
    }

    private static var cache = Cache(locale: locale)

    // MARK: - Dates

    /// « 23 sept. 2026 à 14:05 »
    public static func date(_ date: Date) -> String {
        cache.dateMedium.string(from: date)
    }

    /// « 23 septembre 2026 à 14:05 »
    public static func longDate(_ date: Date) -> String {
        cache.dateLong.string(from: date)
    }

    /// « 14:05 »
    public static func time(_ date: Date) -> String {
        cache.time.string(from: date)
    }

    /// « il y a 12 s », « il y a 3 min », « il y a 2 h », puis la date.
    public static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return L("\(seconds)\(unitSpace)s ago", "il y a \(seconds)\(unitSpace)s") }
        if seconds < 3600 { return L("\(seconds / 60)\(unitSpace)min ago", "il y a \(seconds / 60)\(unitSpace)min") }
        if seconds < 24 * 3600 { return L("\(seconds / 3600)\(unitSpace)h ago", "il y a \(seconds / 3600)\(unitSpace)h") }
        return Self.date(date)
    }

    // MARK: - Nombres

    public static func integer(_ value: UInt64) -> String {
        cache.integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func integer(_ value: Int) -> String {
        cache.integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Nombre à une décimale au plus : « 3 012,4 », « 2 ».
    public static func decimal(_ value: Double) -> String {
        cache.decimal1.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    public static func percentage(_ value: Double) -> String {
        "\(cache.percent.string(from: NSNumber(value: value)) ?? "\(value)")\(unitSpace)%"
    }

    // MARK: - Tailles

    /// Unités décimales (1 Go = 10⁹ octets), comme le Finder et les fabricants de disques.
    public static func bytes(_ bytes: UInt64) -> String {
        let units: [(Double, String)] = [
            (1e12, L("TB", "To")), (1e9, L("GB", "Go")), (1e6, L("MB", "Mo")), (1e3, L("kB", "ko"))
        ]
        let value = Double(bytes)
        for (index, (factor, unit)) in units.enumerated() {
            guard value >= factor else { continue }
            let scaled = value / factor
            // 999,96 Go s'affiche « 1 To », pas « 1 000 Go ».
            if index > 0, (scaled * 10).rounded() / 10 >= 1000 {
                return "\(decimal(value / units[index - 1].0))\(unitSpace)\(units[index - 1].1)"
            }
            return "\(decimal(scaled))\(unitSpace)\(unit)"
        }
        return "\(integer(bytes))\(unitSpace)\(L("bytes", "octets"))"
    }

    /// Unités de données NVMe (1 unité = 1 000 × 512 octets) converties en octets, sans débordement.
    public static func dataUnitsToBytes(_ units: UInt64) -> UInt64 {
        units.saturatingMultiplied(by: 512_000)
    }

    public static func dataUnitsToBytesText(_ units: UInt64) -> String {
        bytes(dataUnitsToBytes(units))
    }

    public static func largeNumber(_ value: UInt64) -> String {
        let v = Double(value)
        if v >= 1e9 { return L("about \(decimal(v / 1e9))\(unitSpace)B", "environ \(decimal(v / 1e9))\(unitSpace)Md") }
        if v >= 1e6 { return L("about \(decimal(v / 1e6))\(unitSpace)M", "environ \(decimal(v / 1e6))\(unitSpace)M") }
        return integer(value)
    }

    // MARK: - Durées et mesures

    public static func hours(_ value: UInt64) -> String {
        "\(integer(value))\(unitSpace)h"
    }

    /// Équivalent lisible d'un nombre d'heures : « 143 jours », « 5 mois », « 3,6 ans ».
    public static func approximateDuration(hours: UInt64) -> String {
        let days = Double(hours) / 24
        if days < 1 { return L("less than a day", "moins d'un jour") }
        if days < 60 {
            let d = Int(days.rounded())
            return "\(d)\(unitSpace)\(L("day", "jour"))\(d > 1 ? "s" : "")"
        }
        let months = days / 30.44
        if months < 24 { return "\(Int(months.rounded()))\(unitSpace)\(L("months", "mois"))" }
        return "\(decimal(days / 365.25))\(unitSpace)\(L("years", "ans"))"
    }

    public static func cycles(_ value: UInt64) -> String {
        integer(value)
    }

    public static func temperature(_ celsius: Int) -> String {
        "\(celsius)\(unitSpace)°C"
    }

    /// Unité de débit : 10⁶ octets par seconde.
    public static var speedUnit: String { L("MB/s", "Mo/s") }

    /// Débit en Mo/s (10⁶ octets par seconde).
    public static func speed(_ megabytesPerSecond: Double) -> String {
        "\(decimal(megabytesPerSecond))\(unitSpace)\(speedUnit)"
    }

    public static func speedIOPS(_ iops: Double) -> String {
        "\(integer(UInt64(max(0, iops.rounded()))))\(unitSpace)IOPS"
    }
}

public extension UInt64 {
    /// Multiplication qui plafonne à `UInt64.max` au lieu de faire planter l'app.
    /// Certaines valeurs S.M.A.R.T. brutes sont codées sur 48 bits par le fabricant :
    /// multipliées par une taille de bloc, elles peuvent dépasser 64 bits.
    func saturatingMultiplied(by other: UInt64) -> UInt64 {
        let (result, overflow) = multipliedReportingOverflow(by: other)
        return overflow ? .max : result
    }
}
