import SwiftUI
import Charts
import DiskHealthCore
import BenchmarkCore

/// Page A4 du rapport PDF. Toujours en clair (le PDF est imprimé ou partagé, quel que soit le thème du Mac).
struct ReportPageView: View {
    enum Page { case summary, details }

    static let pageSize = CGSize(width: 595, height: 842)

    static func pages(for report: ReportData) -> [Page] {
        report.disk.snapshot == nil && report.benchmark == nil ? [.summary] : [.summary, .details]
    }

    let report: ReportData
    let page: Page
    let pageNumber: Int
    let pageCount: Int

    private var disk: RealDisk { report.disk }

    private enum Palette {
        static let text = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let secondary = Color(red: 0.43, green: 0.43, blue: 0.45)
        static let rule = Color(red: 0.90, green: 0.90, blue: 0.92)
        static let stripe = Color(red: 0.965, green: 0.965, blue: 0.97)
        static let accent = Color(red: 0.18, green: 0.62, blue: 0.84)

        static func status(_ status: HealthStatus) -> Color {
            switch status {
            case .good: return Color(red: 0.14, green: 0.54, blue: 0.24)
            case .caution: return Color(red: 0.79, green: 0.20, blue: 0.0)
            case .bad: return Color(red: 0.84, green: 0.0, blue: 0.08)
            case .unknown: return secondary
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.vertical, 14)
            switch page {
            case .summary: summaryPage
            case .details: detailsPage
            }
            Spacer(minLength: 0)
            Text(ExportService.methodText.joined(separator: " "))
                .font(.system(size: 7.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .light)
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aman Disk").font(.system(size: 14, weight: .bold))
                Text(L("Drive health report", "Rapport de santé du disque")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.longDate(report.generatedAt))
                Text(L("Page \(pageNumber) of \(pageCount)", "Page \(pageNumber) sur \(pageCount)"))
            }
            .font(.system(size: 9))
            .foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Page 1

    private var summaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(disk.physical.model).font(.system(size: 18, weight: .bold))
                Text("\(Formatters.bytes(disk.physical.sizeBytes)) · \(disk.physical.mediumLabel) \(disk.physical.locationLabel.lowercased()) · \(disk.physical.interfaceLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
            }

            // Verdict
            HStack(spacing: 0) {
                Rectangle().fill(Palette.status(disk.health.status)).frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(disk.health.status.localizedLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.status(disk.health.status))
                    ForEach(disk.health.reasons, id: \.self) { reason in
                        Text(reason).font(.system(size: 10))
                    }
                    Text(L("Remaining life: ", "Durée de vie restante : ") + (disk.knownLifePercent.map { "\($0)\(Formatters.unitSpace)%" } ?? L("not reported by this drive", "non fournie par ce disque")))
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                Spacer(minLength: 0)
            }
            .background(Palette.status(disk.health.status).opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            sectionHeader("Identification")
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 5) {
                    infoRow(L("Model", "Modèle"), disk.physical.model)
                    infoRow(L("Serial number", "Numéro de série"), report.serialText)
                    infoRow("Firmware", disk.firmware ?? L("Unknown", "Inconnu"))
                }
                VStack(alignment: .leading, spacing: 5) {
                    infoRow(L("Capacity", "Capacité"), Formatters.bytes(disk.physical.sizeBytes))
                    infoRow("Interface", disk.physical.interfaceLabel)
                    infoRow(L("Read on", "Relevé"), Formatters.date(disk.lastRead))
                }
            }

            if let metrics = disk.metrics {
                sectionHeader(L("Key indicators", "Indicateurs clés"))
                let items = ExportService.keyIndicators(metrics, disk: disk)
                let half = (items.count + 1) / 2
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items.prefix(half), id: \.0) { infoRow($0.0, $0.1) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items.dropFirst(half), id: \.0) { infoRow($0.0, $0.1) }
                    }
                }
            }

            if report.options.includeHistory {
                sectionHeader(L("Temperature over 7 days", "Température sur 7 jours"))
                if report.history.points.count >= 2 {
                    historyChart
                        .frame(height: 150)
                    Text(TemperatureHistoryView.legendText(report.history))
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text(L("Not enough measurements yet.", "Pas encore assez de mesures."))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private var historyChart: some View {
        let agg = report.history
        let yMin = Double(max(0, (agg.min ?? 0) - 5))
        let yMax = Double((agg.max ?? 0) + 5)
        let end = report.generatedAt
        return Chart(agg.points) { point in
            if let lo = point.minTemperature, let hi = point.maxTemperature {
                AreaMark(x: .value("Date", point.date), yStart: .value("Min", lo), yEnd: .value("Max", hi),
                         series: .value("Segment", point.segment))
                    .foregroundStyle(Palette.accent.opacity(0.18))
            }
            LineMark(x: .value("Date", point.date), y: .value("Moyenne", point.temperature),
                     series: .value("Segment", point.segment))
                .foregroundStyle(Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        .chartXScale(domain: end.addingTimeInterval(-7 * 24 * 3600)...end)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v)) °C").font(.system(size: 8)).foregroundStyle(Palette.secondary) }
                }
            }
        }
    }

    // MARK: Page 2

    private var detailsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = disk.snapshot {
                smartTable(snapshot)
            }
            if let bench = report.benchmark {
                benchmarkSection(bench)
            }
        }
    }

    private func smartTable(_ snapshot: DiskHealthSnapshot) -> some View {
        let rows = SmartRows.rows(for: snapshot)
        let isATA: Bool = { if case .ata = snapshot { return true } else { return false } }()
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(isATA ? L("S.M.A.R.T. attributes", "Attributs S.M.A.R.T.") : L("NVMe SMART / Health log", "Journal NVMe SMART / Health"))
                .padding(.bottom, 6)
            HStack(spacing: 6) {
                Text("ID").frame(width: 30, alignment: .leading)
                Text(L("Attribute", "Attribut")).frame(maxWidth: .infinity, alignment: .leading)
                if isATA {
                    Text(L("Cur.", "Act.")).frame(width: 28, alignment: .trailing)
                    Text(L("Worst", "Pire")).frame(width: 28, alignment: .trailing)
                    Text(L("Thres.", "Seuil")).frame(width: 30, alignment: .trailing)
                }
                Text(L("Value", "Valeur")).frame(width: 100, alignment: .trailing)
                Text(L("Status", "État")).frame(width: 62, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .padding(.vertical, 3)
            .background(Palette.stripe)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, attr in
                HStack(spacing: 6) {
                    Text(attr.hexID).font(.system(size: 8.5, design: .monospaced)).frame(width: 30, alignment: .leading)
                    Text(attr.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if isATA {
                        Text(attr.current ?? "").frame(width: 28, alignment: .trailing)
                        Text(attr.worst ?? "").frame(width: 28, alignment: .trailing)
                        Text(attr.threshold ?? "").frame(width: 30, alignment: .trailing)
                    }
                    Text(attr.value).lineLimit(1).frame(width: 100, alignment: .trailing)
                    Text(attr.state.localizedLabel)
                        .foregroundStyle(attr.state == .normal || attr.state == .informational ? Palette.text : Palette.status(attr.state == .critical ? .bad : .caution))
                        .frame(width: 62, alignment: .leading)
                }
                .font(.system(size: 8.5))
                .padding(.vertical, 2.5)
                .background(index.isMultiple(of: 2) ? Color.white : Palette.stripe)
            }
        }
    }

    private func benchmarkSection(_ res: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L("Latest performance test", "Dernier test de performances"))
            Text(L("\(Formatters.date(res.date)) · \(res.profile.label), \(res.fileSize >> 30) GiB file · volume “\(res.conditions.volumeName)”", "\(Formatters.date(res.date)) · \(res.profile.label), fichier de \(res.fileSize >> 30) Gio · volume « \(res.conditions.volumeName) »"))
                .font(.system(size: 9))
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 0) {
                Text("Test").frame(width: 110, alignment: .leading)
                Text(L("Read", "Lecture")).frame(width: 110, alignment: .trailing)
                Text(L("Write", "Écriture")).frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            ForEach(BenchTestSpec.defaultGrid, id: \.id) { spec in
                HStack(spacing: 0) {
                    Text(spec.label).frame(width: 110, alignment: .leading)
                    Text(ExportService.speedText(res, spec, .read)).frame(width: 110, alignment: .trailing)
                    Text(res.profile.includesWrites ? ExportService.speedText(res, spec, .write) : L("not tested", "non testé")).frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 9))
                .monospacedDigit()
            }
            Text(ExportService.benchmarkConditions(res))
                .font(.system(size: 8))
                .foregroundStyle(Palette.secondary)
            Text(Strings.benchHelpValues)
                .font(.system(size: 8))
                .foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Outils

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Rectangle().fill(Palette.rule).frame(height: 1)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .foregroundStyle(Palette.secondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
        }
        .font(.system(size: 10))
    }
}
