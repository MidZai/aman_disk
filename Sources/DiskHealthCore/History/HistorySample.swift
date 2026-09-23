import Foundation

public struct HistorySample: Codable, Hashable {
    public let date: Date
    /// Température mesurée ; pour un échantillon compacté, moyenne arrondie de la tranche.
    public let temperatureC: Int?
    public let percentageUsed: Int?
    public let dataUnitsWritten: UInt64?
    public let dataUnitsRead: UInt64?
    public let powerOnHours: UInt64?
    public let mediaErrors: UInt64?
    public let availableSpare: Int?
    // v0.9 : présents uniquement sur les échantillons compactés (tranches de 5 min).
    // Optionnels, donc les anciens fichiers d'historique se relisent sans conversion.
    public let temperatureMinC: Int?
    public let temperatureMaxC: Int?
    /// Nombre de mesures réelles représentées par cet échantillon (nil = 1).
    public let sampleCount: Int?

    public init(date: Date, temperatureC: Int?, percentageUsed: Int?, dataUnitsWritten: UInt64?, dataUnitsRead: UInt64?, powerOnHours: UInt64?, mediaErrors: UInt64?, availableSpare: Int?, temperatureMinC: Int? = nil, temperatureMaxC: Int? = nil, sampleCount: Int? = nil) {
        self.date = date
        self.temperatureC = temperatureC
        self.percentageUsed = percentageUsed
        self.dataUnitsWritten = dataUnitsWritten
        self.dataUnitsRead = dataUnitsRead
        self.powerOnHours = powerOnHours
        self.mediaErrors = mediaErrors
        self.availableSpare = availableSpare
        self.temperatureMinC = temperatureMinC
        self.temperatureMaxC = temperatureMaxC
        self.sampleCount = sampleCount
    }

    public var measurementCount: Int { sampleCount ?? 1 }
    public var isCompacted: Bool { sampleCount != nil }
}

extension HistorySample {
    /// Convertit une lecture de santé en échantillon d'historique.
    public static func from(snapshot: DiskHealthSnapshot, date: Date = Date()) -> HistorySample {
        switch snapshot {
        case .nvme(let smartLog, _):
            return HistorySample(
                date: date,
                temperatureC: smartLog.temperatureCelsius,
                percentageUsed: Int(smartLog.percentageUsed),
                dataUnitsWritten: smartLog.dataUnitsWritten,
                dataUnitsRead: smartLog.dataUnitsRead,
                powerOnHours: smartLog.powerOnHours,
                mediaErrors: smartLog.mediaErrors,
                availableSpare: Int(smartLog.availableSpare)
            )
        case .ata(let ataSnapshot):
            let profile = ATACatalog.profile(for: ataSnapshot.model)
            var temp: Int? = nil
            // B6: valeurs stockées en octets ; la conversion lisible se fait à l'affichage.
            var written: UInt64? = nil
            var read: UInt64? = nil
            var hours: UInt64? = nil
            var used: Int? = nil
            var errors: UInt64? = nil
            for attr in ataSnapshot.attributes {
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                switch info.role {
                case .temperature:
                    temp = attr.value(for: .temperature).map { Int($0) }
                case .hostWritesBytes(let mult):
                    written = attr.rawValue * mult
                case .hostReadsBytes(let mult):
                    read = attr.rawValue * mult
                case .powerOnHours:
                    hours = attr.value(for: .powerOnHours)
                case .lifeRemainingPercentNormalized:
                    used = 100 - Int(attr.current)
                case .reallocated, .pending, .uncorrectable:
                    errors = (errors ?? 0) + attr.rawValue
                default:
                    break
                }
            }
            // ATA n'expose pas de réserve disponible.
            return HistorySample(date: date, temperatureC: temp, percentageUsed: used, dataUnitsWritten: written, dataUnitsRead: read, powerOnHours: hours, mediaErrors: errors, availableSpare: nil)
        }
    }
}

extension DiskIdentity {
    /// Clé d'historique d'un disque, dérivée du modèle et du numéro de série.
    public static func key(for snapshot: DiskHealthSnapshot) -> String {
        switch snapshot {
        case .nvme(_, let id): return key(model: id.modelNumber, serial: id.serialNumber)
        case .ata(let ata): return key(model: ata.model, serial: ata.serialNumber)
        }
    }
}
