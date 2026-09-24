import Foundation

/// Indicateurs clés d'un relevé, extraits une seule fois quel que soit le protocole.
/// Source unique pour les tuiles, le panneau de la barre des menus, les rapports et l'historique :
/// avant, chaque vue refaisait cette extraction à sa façon et les chiffres pouvaient diverger.
public struct DiskMetrics: Equatable, Codable {
    public let temperatureC: Int?
    public let powerOnHours: UInt64?
    public let powerCycles: UInt64?
    public let unsafeShutdowns: UInt64?
    public let bytesWritten: UInt64?
    public let bytesRead: UInt64?
    /// Durée de vie restante déclarée par le disque (100 − « pourcentage utilisé » en NVMe).
    public let lifeRemainingPercent: Int?
    /// Endurance consommée déclarée par le disque ; peut dépasser 100 % en NVMe.
    public let percentageUsed: Int?
    public let availableSparePercent: Int?
    /// NVMe : erreurs de données non corrigées (« Media and Data Integrity Errors »).
    public let mediaErrors: UInt64?
    /// ATA : secteurs réalloués + secteurs en attente de réallocation.
    public let badSectors: UInt64?

    public init(snapshot: DiskHealthSnapshot) {
        switch snapshot {
        case .nvme(let log, _):
            temperatureC = log.temperatureCelsius
            powerOnHours = log.powerOnHours
            powerCycles = log.powerCycles
            unsafeShutdowns = log.unsafeShutdowns
            bytesWritten = Formatters.dataUnitsToBytes(log.dataUnitsWritten)
            bytesRead = Formatters.dataUnitsToBytes(log.dataUnitsRead)
            percentageUsed = Int(log.percentageUsed)
            lifeRemainingPercent = max(0, 100 - Int(log.percentageUsed))
            availableSparePercent = Int(log.availableSpare)
            mediaErrors = log.mediaErrors
            badSectors = nil

        case .ata(let ata):
            let profile = ATACatalog.profile(for: ata.model)
            var temperature: Int?
            var temperatureIsPrimary = false
            var hours: UInt64?
            var cycles: UInt64?
            var unsafe: UInt64?
            var written: UInt64?
            var read: UInt64?
            var life: Int?
            var sectors: UInt64?
            for attr in ata.attributes {
                let role = ATACatalog.attributeInfo(id: attr.id, profile: profile).role
                switch role {
                case .temperature:
                    // 0xC2 (194) est la température du disque ; 0xBE (190), celle du flux d'air.
                    guard let t = attr.value(for: role) else { break }
                    if attr.id == 0xC2 || !temperatureIsPrimary {
                        temperature = Int(t)
                        temperatureIsPrimary = attr.id == 0xC2
                    }
                case .powerOnHours: hours = attr.value(for: role)
                case .powerCycles: cycles = attr.value(for: role)
                case .unsafeShutdowns: unsafe = attr.value(for: role)
                case .hostWritesBytes: written = attr.value(for: role)
                case .hostReadsBytes: read = attr.value(for: role)
                case .lifeRemainingPercentNormalized: life = max(0, min(100, Int(attr.current)))
                case .reallocated, .pending: sectors = (sectors ?? 0) &+ attr.rawValue
                case .uncorrectable, .none: break
                }
            }
            temperatureC = temperature
            powerOnHours = hours
            powerCycles = cycles
            unsafeShutdowns = unsafe
            bytesWritten = written
            bytesRead = read
            lifeRemainingPercent = life
            percentageUsed = life.map { 100 - $0 }
            availableSparePercent = nil
            mediaErrors = nil
            badSectors = sectors
        }
    }
}
