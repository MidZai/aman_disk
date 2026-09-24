import SwiftUI
import Charts
import DiskHealthCore

/// Temperature history of a drive: range picker, curve, gaps and legend.
///
/// Performance: readings are loaded off the main thread and aggregated once per
/// load (not on every render). Hovering is isolated in `ChartHoverOverlay`: moving the
/// mouse only redraws the marker and the tooltip, not the hundreds of points of the curve.
struct TemperatureHistoryView: View {
    let historyKey: String?
    /// Changes with every new reading: triggers the reload.
    let lastRead: Date

    @AppStorage("temperatureHistoryRange") private var range: HistoryRange = .oneHour
    @State private var aggregation: AggregationResult = .empty
    @State private var domainEnd = Date()
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Temperature history", "Historique de température"))
                    .font(.title3.bold())
                Spacer()
                Picker(L("Range", "Plage"), selection: $range) {
                    Text(L("1 hour", "1 heure")).tag(HistoryRange.oneHour)
                    Text(L("24 hours", "24 heures")).tag(HistoryRange.twentyFourHours)
                    Text(L("7 days", "7 jours")).tag(HistoryRange.sevenDays)
                    Text(L("30 days", "30 jours")).tag(HistoryRange.thirtyDays)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // Fewer than 3 readings: no usable curve.
            if aggregation.points.count < 2 || aggregation.measurementCount < 3 {
                emptyState
            } else {
                TemperatureChart(aggregation: aggregation, range: range, domainEnd: domainEnd)
                    .frame(height: 220)
                Text(Self.legendText(aggregation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .task(id: LoadKey(historyKey: historyKey, range: range, lastRead: lastRead)) {
            await load()
        }
    }

    private struct LoadKey: Equatable {
        let historyKey: String?
        let range: HistoryRange
        let lastRead: Date
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "thermometer.medium")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(hasLoaded ? L("Not enough measurements yet.", "Pas encore assez de mesures.") : L("Loading…", "Chargement…"))
                .font(.headline)
            if hasLoaded {
                Text(L("Aman measures the temperature every 30 seconds. Keep it in the menu bar for continuous tracking.", "Aman mesure la température toutes les 30 secondes. Laissez-le dans la barre des menus pour un suivi continu."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    static func legendText(_ agg: AggregationResult) -> String {
        var parts: [String] = []
        if let v = agg.min { parts.append(L("Min \(Formatters.temperature(v))", "Min \(Formatters.temperature(v))")) }
        if let v = agg.average { parts.append(L("Average \(Formatters.temperature(v))", "Moyenne \(Formatters.temperature(v))")) }
        if let v = agg.max { parts.append("Max \(Formatters.temperature(v))") }
        let n = agg.measurementCount
        parts.append("\(Formatters.integer(n)) \(n > 1 ? L("measurements", "mesures") : L("measurement", "mesure"))")
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let historyKey else {
            aggregation = .empty
            hasLoaded = true
            return
        }
        let range = self.range
        let now = Date()
        let samples = await HistoryStore.shared.loadSamples(for: historyKey, since: now.addingTimeInterval(-range.timeInterval))
        let result = await Task.detached(priority: .userInitiated) {
            HistoryAggregation.aggregate(samples: samples, range: range)
        }.value
        guard !Task.isCancelled else { return }
        domainEnd = now
        if result != aggregation { aggregation = result }
        hasLoaded = true
    }
}

extension HistoryRange {
    var axisDateFormat: Date.FormatStyle {
        switch self {
        case .oneHour, .twentyFourHours: return .dateTime.hour().minute()
        case .sevenDays: return .dateTime.weekday(.abbreviated).day()
        case .thirtyDays: return .dateTime.day().month(.abbreviated)
        }
    }
}

/// The curve itself: only depends on the aggregated data, never on the mouse position.
private struct TemperatureChart: View {
    let aggregation: AggregationResult
    let range: HistoryRange
    let domainEnd: Date

    var body: some View {
        let yMin = Double(max(0, (aggregation.min ?? 0) - 5))
        let yMax = Double(min(110, (aggregation.max ?? 0) + 5))

        Chart {
            ForEach(aggregation.points) { point in
                if range.showsMinMaxBand, let lo = point.minTemperature, let hi = point.maxTemperature {
                    AreaMark(
                        x: .value("Heure", point.date),
                        yStart: .value("Min", lo),
                        yEnd: .value("Max", hi),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                } else {
                    AreaMark(
                        x: .value("Heure", point.date),
                        yStart: .value("Base", yMin),
                        yEnd: .value("Temp", point.temperature),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
                LineMark(
                    x: .value("Heure", point.date),
                    y: .value("Temp", point.temperature),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .chartXScale(domain: domainEnd.addingTimeInterval(-range.timeInterval)...domainEnd)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: range.axisDateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))\(Formatters.unitSpace)°") }
                }
            }
        }
        .chartBackground { proxy in
            GapHatching(proxy: proxy, gaps: aggregation.gaps)
        }
        .chartOverlay { proxy in
            ChartHoverOverlay(proxy: proxy, aggregation: aggregation, range: range)
        }
        .accessibilityLabel(L("Temperature chart", "Courbe de température"))
        .accessibilityValue(TemperatureHistoryView.legendText(aggregation))
    }
}

/// Gaps: very subtle hatched band, with no line or fill.
private struct GapHatching: View {
    let proxy: ChartProxy
    let gaps: [DateInterval]

    var body: some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                ForEach(gaps, id: \.self) { gap in
                    if let x0 = proxy.position(forX: gap.start), let x1 = proxy.position(forX: gap.end), x1 > x0 {
                        HatchPattern()
                            .stroke(.quaternary, lineWidth: 1)
                            .frame(width: x1 - x0, height: plot.height)
                            .clipped()
                            .offset(x: plot.minX + x0, y: plot.minY)
                    }
                }
            }
        }
    }
}

/// Vertical marker and tooltip. Only this view depends on the mouse position.
private struct ChartHoverOverlay: View {
    let proxy: ChartProxy
    let aggregation: AggregationResult
    let range: HistoryRange
    @State private var hoverX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoverX = location.x
                        case .ended: hoverX = nil
                        }
                    }

                if let hoverX, plot.width > 0, let date = proxy.value(atX: hoverX - plot.minX, as: Date.self) {
                    marker(date: date, plot: plot, containerWidth: geo.size.width)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(date: Date, plot: CGRect, containerWidth: CGFloat) -> some View {
        let gap = aggregation.gaps.first { $0.contains(date) }
        let point = gap == nil ? nearestPoint(to: date) : nil
        let markerDate = point?.date ?? date
        if let x = proxy.position(forX: markerDate) {
            let xInPlot = plot.minX + x
            Rectangle()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: 1, height: plot.height)
                .offset(x: xInPlot, y: plot.minY)
                .allowsHitTesting(false)

            if let point, let y = proxy.position(forY: point.temperature) {
                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .frame(width: 9, height: 9)
                    .offset(x: xInPlot - 4.5, y: plot.minY + y - 4.5)
                    .allowsHitTesting(false)
            }

            let tooltipWidth: CGFloat = gap == nil ? 150 : 196
            tooltip(for: gap, point: point)
                .offset(x: min(max(0, xInPlot - tooltipWidth / 2), containerWidth - tooltipWidth), y: plot.minY + 4)
                .allowsHitTesting(false)
        }
    }

    private func nearestPoint(to date: Date) -> AggregatedPoint? {
        // Points sorted by date: binary search rather than a full scan on every move.
        let points = aggregation.points
        guard !points.isEmpty else { return nil }
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(points[lo - 1].date.timeIntervalSince(date)) < abs(points[lo].date.timeIntervalSince(date)) {
            return points[lo - 1]
        }
        return points[lo]
    }

    @ViewBuilder
    private func tooltip(for gap: DateInterval?, point: AggregatedPoint?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let gap {
                Text("\(dateLabel(gap.start)) – \(dateLabel(gap.end))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(L("No measurements (Mac asleep or Aman closed)", "Aucune mesure (Mac en veille ou Aman fermé)"))
                    .font(.caption.bold())
                    .fixedSize(horizontal: false, vertical: true)
            } else if let point {
                Text(dateLabel(point.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(valueLabel(point))
                    .font(.caption.bold())
                    .monospacedDigit()
            }
        }
        .frame(width: gap == nil ? nil : 180, alignment: .leading)
        .fixedSize(horizontal: gap == nil, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private func dateLabel(_ date: Date) -> String {
        range == .oneHour ? Formatters.time(date) : Formatters.date(date)
    }

    private func valueLabel(_ point: AggregatedPoint) -> String {
        let avg = Formatters.temperature(Int(point.temperature.rounded()))
        if range != .oneHour, let lo = point.minTemperature, let hi = point.maxTemperature, lo != hi {
            return L("\(avg) average (\(Int(lo.rounded())) to \(Int(hi.rounded()))\(Formatters.unitSpace)°C)", "\(avg) en moyenne (\(Int(lo.rounded())) à \(Int(hi.rounded()))\(Formatters.unitSpace)°C)")
        }
        return avg
    }
}

/// Diagonal hatching that fills the frame.
private struct HatchPattern: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
