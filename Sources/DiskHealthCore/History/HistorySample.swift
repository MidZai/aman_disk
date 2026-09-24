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
    /// ATA : les volumes écrits et lus sont stockés en octets ; la conversion lisible se fait à l'affichage.
    public static func from(snapshot: DiskHealthSnapshot, date: Date = Date()) -> HistorySample {
        let m = DiskMetrics(snapshot: snapshot)
        switch snapshot {
        case .nvme(let smartLog, _):
            return HistorySample(
                date: date,
                temperatureC: m.temperatureC,
                percentageUsed: m.percentageUsed,
                dataUnitsWritten: smartLog.dataUnitsWritten,
                dataUnitsRead: smartLog.dataUnitsRead,
                powerOnHours: m.powerOnHours,
                mediaErrors: m.mediaErrors,
                availableSpare: m.availableSparePercent
            )
        case .ata:
            return HistorySample(date: date, temperatureC: m.temperatureC, percentageUsed: m.percentageUsed, dataUnitsWritten: m.bytesWritten, dataUnitsRead: m.bytesRead, powerOnHours: m.powerOnHours, mediaErrors: m.badSectors, availableSpare: nil)
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
