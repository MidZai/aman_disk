import SwiftUI
import DiskHealthCore

/// Indicator tile: value, label (always shown) and an optional detail.
struct StatTile: View {
    let label: String
    let value: String?
    var detail: String? = nil
    var detailColor: Color = .secondary
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value ?? "—")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value == nil ? L("Not reported by this drive", "Non fourni par ce disque") : (detail ?? " "))
                .font(.caption)
                .foregroundStyle(value == nil ? .secondary : detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

/// Key indicators, shared by NVMe and ATA. One row of five tiles when there's room,
/// otherwise two rows (narrow window, inspector open) instead of squeezing the values.
struct StatTilesGrid: View {
    let disk: RealDisk
    let metrics: DiskMetrics

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tiles }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) { tiles }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        temperatureTile
        StatTile(
                label: L("Data written", "Données écrites"),
                value: metrics.bytesWritten.map(Formatters.bytes),
                detail: metrics.bytesRead.map { L("Read: \(Formatters.bytes($0))", "Lues : \(Formatters.bytes($0))") },
                help: L("Total amount written to the drive since it was made: the main cause of SSD wear.", "Volume total écrit sur le disque depuis sa fabrication : principal facteur d'usure d'un SSD.")
            )
            StatTile(
                label: L("Power-on hours", "Heures de fonctionnement"),
                value: metrics.powerOnHours.map(Formatters.hours),
                detail: metrics.powerOnHours.map { L("≈ \(Formatters.approximateDuration(hours: $0)) powered on", "≈ \(Formatters.approximateDuration(hours: $0)) sous tension") }
            )
            StatTile(
                label: L("Power cycles", "Démarrages"),
                value: metrics.powerCycles.map(Formatters.cycles),
                detail: metrics.unsafeShutdowns.map { L("including \(Formatters.integer($0)) unsafe shutdowns", "dont \(Formatters.integer($0)) arrêts non propres") },
                help: L("Number of times the drive was powered on. Unsafe shutdowns (power loss, crash) are common and usually harmless.", "Nombre de mises sous tension. Les arrêts non propres (coupure de courant, plantage) sont courants et généralement sans gravité.")
            )
        errorsTile
    }

    private var temperatureTile: some View {
        let status = TemperatureStatus.evaluate(temperatureCelsius: metrics.temperatureC, identify: disk.identify,
                                                isRotational: disk.physical.mediumType == .rotational)
        return StatTile(
            label: L("Temperature", "Température"),
            value: metrics.temperatureC.map(Formatters.temperature),
            detail: status.label,
            detailColor: status.color
        )
    }

    @ViewBuilder
    private var errorsTile: some View {
        if case .nvme = disk.snapshot {
            let errors = metrics.mediaErrors ?? 0
            StatTile(
                label: L("Data errors", "Erreurs de données"),
                value: metrics.mediaErrors.map(Formatters.integer),
                detail: errors == 0 ? L("No uncorrected errors", "Aucune erreur non corrigée") : L("Back up your data", "Sauvegardez vos données"),
                detailColor: errors == 0 ? .secondary : .orange,
                help: L("Read or write errors the controller could not correct (Media and Data Integrity Errors).", "Erreurs de lecture ou d'écriture que le contrôleur n'a pas pu corriger (Media and Data Integrity Errors).")
            )
        } else {
            let sectors = metrics.badSectors ?? 0
            StatTile(
                label: L("Bad sectors", "Secteurs défectueux"),
                value: metrics.badSectors.map(Formatters.integer),
                detail: sectors == 0 ? L("No sectors replaced", "Aucun secteur remplacé") : L("Reallocated and pending", "Réalloués et en attente"),
                detailColor: sectors == 0 ? .secondary : .orange,
                help: L("Reallocated sectors (attribute 5) and sectors pending reallocation (attribute 197).", "Secteurs réalloués (attribut 5) et secteurs en attente de réallocation (attribut 197).")
            )
        }
    }
}
