import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DiskHealthCore
import BenchmarkCore

struct ExportOptions {
    var includeSerial = false
    var includeHistory = true
}

/// Contents of a report, gathered once for all three formats.
struct ReportData {
    let disk: RealDisk
    let options: ExportOptions
    let benchmark: BenchmarkResult?
    /// 7-day history, as hourly averages (empty if not requested).
    let history: AggregationResult
    let generatedAt: Date

    /// Serial number as it must appear in the report.
    var serialText: String {
        options.includeSerial ? (disk.serialNumber ?? L("Unknown", "Inconnu")) : L("Hidden", "Masqué")
    }

    /// Reading without the serial number when it must not appear in the report (NVMe and ATA).
    var exportedSnapshot: DiskHealthSnapshot? {
        guard !options.includeSerial, let snapshot = disk.snapshot else { return disk.snapshot }
        switch snapshot {
        case .nvme(let smart, let id):
            return .nvme(smart, NVMeIdentify(serialNumber: "", modelNumber: id.modelNumber, firmwareRevision: id.firmwareRevision,
                                             warningTempKelvin: id.warningTempKelvin, criticalTempKelvin: id.criticalTempKelvin,
                                             totalCapacityBytes: id.totalCapacityBytes))
        case .ata(let a):
            return .ata(ATASmartSnapshot(attributes: a.attributes, model: a.model, firmware: a.firmware, serialNumber: "",
                                         rotationRate: a.rotationRate, thresholdExceeded: a.thresholdExceeded,
                                         checksumValid: a.checksumValid, thresholdsChecksumValid: a.thresholdsChecksumValid))
        }
    }

    @MainActor
    static func collect(disk: RealDisk, options: ExportOptions) -> ReportData {
        var history = AggregationResult.empty
        if options.includeHistory, let key = disk.historyKey {
            let samples = HistoryStore.shared.samples(for: key, since: Date().addingTimeInterval(-7 * 24 * 3600))
            history = HistoryAggregation.aggregate(samples: samples, range: .sevenDays)
        }
        return ReportData(disk: disk, options: options,
                          benchmark: BenchmarkHistoryManager.shared.results(for: disk).first,
                          history: history, generatedAt: Date())
    }
}

enum ExportService {

    // MARK: - Entry point

    @MainActor
    static func export(disk: RealDisk, format: ReportFormat, options: ExportOptions) {
        let ext: String
        switch format {
        case .pdf: ext = "pdf"
        case .text: ext = "txt"
        case .json: ext = "json"
        }
        guard let url = saveURL(disk: disk, extension: ext) else { return }
        let report = ReportData.collect(disk: disk, options: options)
        do {
            switch format {
            case .pdf: try writePDF(report, to: url)
            case .text: try reportText(report).write(to: url, atomically: true, encoding: .utf8)
            case .json: try reportJSON(report).write(to: url, options: .atomic)
            }
            ToastCenter.shared.show(message: L("Report exported", "Rapport exporté"), systemImage: "checkmark.circle")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            ToastCenter.shared.show(message: L("Export failed: \(error.localizedDescription)", "L'export a échoué : \(error.localizedDescription)"), systemImage: "xmark.octagon")
        }
    }

    @MainActor
    private static func saveURL(disk: RealDisk, extension ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = L("Export Aman Disk Report", "Exporter le rapport Aman Disk")
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safeModel = disk.physical.model.components(separatedBy: invalid).joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        panel.nameFieldStringValue = "Aman-Disk_\(safeModel)_\(formatter.string(from: Date())).\(ext)"
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Summary (clipboard)

    static func summaryText(disk: RealDisk) -> String {
        var lines = ["Aman Disk — \(disk.physical.model)"]
        lines.append("\(Formatters.bytes(disk.physical.sizeBytes)) · \(disk.physical.mediumAndLocationLabel) · \(disk.physical.interfaceLabel)")
        let reason = disk.health.reasons.first ?? L("No problems detected.", "Aucune anomalie détectée.")
        lines.append(L("Status: \(disk.health.status.localizedLabel) — \(reason)", "État : \(disk.health.status.localizedLabel) — \(reason)"))
        if let life = disk.knownLifePercent {
            lines.append(L("Remaining life: \(life)%", "Durée de vie restante : \(life) %"))
        }
        if let m = disk.metrics {
            lines.append(keyIndicators(m, disk: disk).map { L("\($0.0): \($0.1)", "\($0.0) : \($0.1)") }.joined(separator: " · "))
        }
        lines.append(L("Read on \(Formatters.longDate(disk.lastRead))", "Relevé le \(Formatters.longDate(disk.lastRead))"))
        return lines.joined(separator: "\n")
    }

    static func copySummary(disk: RealDisk) {
        copy(summaryText(disk: disk))
    }

    /// Key indicators, in the order of the tiles. Missing value: “Not reported”.
    static func keyIndicators(_ m: DiskMetrics, disk: RealDisk) -> [(String, String)] {
        var items: [(String, String)] = [
            (L("Temperature", "Température"), m.temperatureC.map(Formatters.temperature) ?? L("Not reported", "Non fournie")),
            (L("Data written", "Données écrites"), m.bytesWritten.map(Formatters.bytes) ?? L("Not reported", "Non fourni")),
            (L("Data read", "Données lues"), m.bytesRead.map(Formatters.bytes) ?? L("Not reported", "Non fourni")),
            (L("Power-on hours", "Heures de fonctionnement"), m.powerOnHours.map(Formatters.hours) ?? L("Not reported", "Non fourni")),
            (L("Power cycles", "Démarrages"), m.powerCycles.map(Formatters.integer) ?? L("Not reported", "Non fourni")),
            (L("Unsafe shutdowns", "Arrêts non propres"), m.unsafeShutdowns.map(Formatters.integer) ?? L("Not reported", "Non fourni"))
        ]
        if case .nvme = disk.snapshot {
            items.append((L("Available spare", "Réserve disponible"), m.availableSparePercent.map { "\($0) %" } ?? L("Not reported", "Non fournie")))
            items.append((L("Data errors", "Erreurs de données"), m.mediaErrors.map(Formatters.integer) ?? L("Not reported", "Non fourni")))
        } else {
            items.append((L("Bad sectors", "Secteurs défectueux"), m.badSectors.map(Formatters.integer) ?? L("Not reported", "Non fourni")))
        }
        return items
    }

    // MARK: - Performance test

    static func benchmarkSummary(result: BenchmarkResult) -> String {
        var lines = [L("Aman Disk \(result.appVersion) — Performance test", "Aman Disk \(result.appVersion) — Test de performances")]
        lines.append(L("Date: \(Formatters.date(result.date))", "Date : \(Formatters.date(result.date))"))
        lines.append(L("Volume: ", "Volume : ") + "\(result.conditions.volumeName) (\(result.conditions.fileSystem)\(result.conditions.encrypted == true ? L(", encrypted", ", chiffré") : ""))")
        lines.append(L("Profile: \(result.profile.label), \(result.fileSize >> 30) GiB file", "Profil : \(result.profile.label), fichier de \(result.fileSize >> 30) Gio"))
        lines.append("")
        lines.append(pad("", 14) + padLeft(L("Read", "Lecture"), 16) + padLeft(L("Write", "Écriture"), 16))
        for spec in BenchTestSpec.defaultGrid {
            let read = speedText(result, spec, .read)
            let write = result.profile.includesWrites ? speedText(result, spec, .write) : L("not tested", "non testé")
            lines.append(pad(spec.label, 14) + padLeft(read, 16) + padLeft(write, 16))
        }
        lines.append("")
        lines.append(benchmarkConditions(result))
        if !result.completed {
            lines.append(L("Test interrupted (\(result.stopReason ?? L("unknown reason", "raison inconnue"))): partial results.", "Test interrompu (\(result.stopReason ?? L("unknown reason", "raison inconnue"))) : résultats partiels."))
        }
        return lines.joined(separator: "\n")
    }

    static func copyBenchmarkSummary(result: BenchmarkResult) {
        copy(benchmarkSummary(result: result))
    }

    static func speedText(_ result: BenchmarkResult, _ spec: BenchTestSpec, _ direction: BenchDirection) -> String {
        guard let test = result.tests.first(where: { $0.spec.id == spec.id && $0.direction == direction }),
              let best = BenchMath.best(test.passes) else { return "—" }
        return Formatters.speed(BenchMath.megabytesPerSecond(bytes: best.bytes, seconds: best.seconds))
    }

    /// “Temperature 38 → 51 °C · wrote 21.5 GB · 4K QD1 latency: 85 µs (median), 190 µs (99th percentile) · on power adapter”
    static func benchmarkConditions(_ result: BenchmarkResult) -> String {
        var parts: [String] = []
        let c = result.conditions
        switch (c.temperatureStartC, c.temperatureMaxC) {
        case let (start?, max?): parts.append(L("Temperature \(start) → \(Formatters.temperature(max))", "Température \(start) → \(Formatters.temperature(max))"))
        case let (nil, max?): parts.append(L("Max temperature \(Formatters.temperature(max))", "Température max \(Formatters.temperature(max))"))
        default: parts.append(L("Temperature not recorded", "Température non relevée"))
        }
        parts.append(L("wrote \(Formatters.bytes(c.bytesWritten))", "écrit \(Formatters.bytes(c.bytesWritten))"))
        if let rnd = result.tests.first(where: { $0.spec.id == "RND4K_QD1" && $0.direction == .read }),
           let p50 = rnd.latencyP50Micros, let p99 = rnd.latencyP99Micros {
            parts.append(L("4K QD1 latency: \(Formatters.integer(UInt64(p50))) µs (median), \(Formatters.integer(UInt64(p99))) µs (99th percentile)", "latence 4K QD1 : \(Formatters.integer(UInt64(p50))) µs (médiane), \(Formatters.integer(UInt64(p99))) µs (99 %)"))
        }
        parts.append(c.onBattery == true ? L("on battery", "sur batterie") : L("on power adapter", "sur secteur"))
        if c.lowPowerMode == true { parts.append(L("Low Power Mode", "mode économie d'énergie")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Text

    static func reportText(_ r: ReportData) -> String {
        let disk = r.disk
        let rule = String(repeating: "─", count: 72)
        var lines: [String] = []
        func section(_ title: String) {
            lines.append("")
            lines.append(rule)
            lines.append("  \(title)")
            lines.append(rule)
        }
        func row(_ label: String, _ value: String) {
            lines.append(pad("  \(label)", 30) + value)
        }

        lines.append(String(repeating: "═", count: 72))
        lines.append(L("  DRIVE HEALTH REPORT — Aman Disk \(AppInfo.version)", "  RAPPORT DE SANTÉ DU DISQUE — Aman Disk \(AppInfo.version)"))
        lines.append(String(repeating: "═", count: 72))
        row(L("Report date", "Date du rapport"), Formatters.longDate(r.generatedAt))
        row("Mac", "\(hardwareModel()) — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        section("1. VERDICT")
        row(L("Status", "État"), disk.health.status.localizedLabel)
        for (index, reason) in disk.health.reasons.enumerated() {
            row(index == 0 ? L("Finding", "Constat") : "", reason)
        }
        row(L("Remaining life", "Durée de vie restante"), disk.knownLifePercent.map { "\($0) %" } ?? L("Not reported by this drive", "Non fournie par ce disque"))

        section("2. IDENTIFICATION")
        row(L("Model", "Modèle"), disk.physical.model)
        row(L("Serial number", "Numéro de série"), r.serialText)
        row("Firmware", disk.firmware ?? L("Unknown", "Inconnu"))
        row(L("Capacity", "Capacité"), Formatters.bytes(disk.physical.sizeBytes))
        row("Interface", "\(disk.physical.interfaceLabel), \(disk.physical.locationLabel.lowercased())")
        row(L("Media", "Support"), disk.physical.mediumLabel)

        if let m = disk.metrics {
            section(L("3. KEY INDICATORS", "3. INDICATEURS CLÉS"))
            for (label, value) in keyIndicators(m, disk: disk) { row(label, value) }
        }

        if let snapshot = disk.snapshot {
            let isATA: Bool = { if case .ata = snapshot { return true } else { return false } }()
            section(isATA ? L("4. S.M.A.R.T. ATTRIBUTES", "4. ATTRIBUTS S.M.A.R.T.") : L("4. NVMe SMART / HEALTH LOG", "4. JOURNAL NVMe SMART / HEALTH"))
            if isATA {
                lines.append(L("  ID    Attribute                         Cur. Wrst Thres  Value                  Status", "  ID    Attribut                          Act. Pire Seuil  Valeur                 État"))
            } else {
                lines.append(L("  ID    Attribute                         Value                  Status", "  ID    Attribut                          Valeur                 État"))
            }
            for a in SmartRows.rows(for: snapshot) {
                let name = pad(truncate(a.name, 32), 32)
                let value = pad(truncate(a.value, 21), 21)
                if isATA {
                    lines.append("  \(a.hexID)  \(name)  \(padLeft(a.current ?? "", 4)) \(padLeft(a.worst ?? "", 4)) \(padLeft(a.threshold ?? "", 5))  \(value)  \(a.state.localizedLabel)")
                } else {
                    lines.append("  \(a.hexID)  \(name)  \(value)  \(a.state.localizedLabel)")
                }
            }
        }

        if r.options.includeHistory {
            section(L("5. TEMPERATURE OVER 7 DAYS", "5. TEMPÉRATURE SUR 7 JOURS"))
            if r.history.measurementCount == 0 {
                lines.append(L("  No measurements recorded.", "  Aucune mesure enregistrée."))
            } else {
                lines.append("  \(TemperatureHistoryView.legendText(r.history))")
                lines.append("")
                for day in dailySummary(r.history) {
                    lines.append("  \(pad(day.label, 24))min \(padLeft(day.min, 6))   \(L("avg.", "moy.")) \(padLeft(day.avg, 6))   max \(padLeft(day.max, 6))")
                }
            }
        }

        if let bench = r.benchmark {
            section(L("6. LATEST PERFORMANCE TEST", "6. DERNIER TEST DE PERFORMANCES"))
            lines.append(contentsOf: benchmarkSummary(result: bench).components(separatedBy: "\n").map { "  \($0)" })
        }

        section(L("METHOD AND LIMITATIONS", "MÉTHODE ET LIMITES"))
        lines.append(contentsOf: methodText.map { "  \($0)" })
        lines.append(String(repeating: "═", count: 72))
        return lines.joined(separator: "\n") + "\n"
    }

    static let methodText = Localization.isFrench ? [
        "L'état est calculé à partir des données déclarées par le contrôleur du disque",
        "au moment de la lecture. Il reflète l'usure et les erreurs connues du disque,",
        "mais ne garantit pas l'absence de panne future. Sauvegardez régulièrement vos données."
    ] : [
        "The status is computed from the data reported by the drive controller at the",
        "time of reading. It reflects the drive's wear and known errors, but does not",
        "guarantee it won't fail in the future. Back up your data regularly."
    ]

    struct DaySummary { let label: String; let min: String; let avg: String; let max: String }

    static func dailySummary(_ agg: AggregationResult) -> [DaySummary] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: agg.points) { calendar.startOfDay(for: $0.date) }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Formatters.locale
        dayFormatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return groups.keys.sorted().map { day in
            let points = groups[day] ?? []
            let lo = points.compactMap(\.minTemperature).min() ?? points.map(\.temperature).min() ?? 0
            let hi = points.compactMap(\.maxTemperature).max() ?? points.map(\.temperature).max() ?? 0
            let avg = points.map(\.temperature).reduce(0, +) / Double(max(points.count, 1))
            return DaySummary(label: dayFormatter.string(from: day),
                              min: Formatters.temperature(Int(lo.rounded())),
                              avg: Formatters.temperature(Int(avg.rounded())),
                              max: Formatters.temperature(Int(hi.rounded())))
        }
    }

    // MARK: - JSON

    static func reportJSON(_ r: ReportData) throws -> Data {
        let history: [ExportedTemperaturePoint]? = r.options.includeHistory
            ? r.history.points.map { ExportedTemperaturePoint(date: $0.date, averageC: $0.temperature, minC: $0.minTemperature, maxC: $0.maxTemperature) }
            : nil
        let physical = r.disk.physical
        let out = ExportFormat(generator: "Aman Disk \(AppInfo.version)", physical: physical, smart: r.exportedSnapshot,
                               health: r.disk.health, metrics: r.disk.metrics, lastRead: r.disk.lastRead,
                               benchmark: r.benchmark, temperatureHistory: history)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(out)
    }

    // MARK: - PDF

    @MainActor
    static func writePDF(_ r: ReportData, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: ReportPageView.pageSize.width, height: ReportPageView.pageSize.height)
        let info = [
            kCGPDFContextTitle: L("Health report — \(r.disk.physical.model)", "Rapport de santé — \(r.disk.physical.model)"),
            kCGPDFContextCreator: "Aman Disk \(AppInfo.version)"
        ] as CFDictionary
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let pages = ReportPageView.pages(for: r)
        for (index, page) in pages.enumerated() {
            let renderer = ImageRenderer(content: ReportPageView(report: r, page: page, pageNumber: index + 1, pageCount: pages.count))
            renderer.proposedSize = ProposedViewSize(ReportPageView.pageSize)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
    }

    // MARK: - Helpers

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    static func pad(_ s: String, _ length: Int) -> String {
        s.count >= length ? s : s + String(repeating: " ", count: length - s.count)
    }

    static func padLeft(_ s: String, _ length: Int) -> String {
        s.count >= length ? s : String(repeating: " ", count: length - s.count) + s
    }

    static func truncate(_ s: String, _ length: Int) -> String {
        s.count <= length ? s : String(s.prefix(length - 1)) + "…"
    }
}
