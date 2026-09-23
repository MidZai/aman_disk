import SwiftUI
import Charts
import DiskHealthCore

/// Historique de température d'un disque : sélecteur de plage, courbe, coupures et légende.
struct TemperatureHistoryView: View {
    let historyKey: String?
    /// Change à chaque nouvelle mesure : déclenche le rechargement.
    let lastRead: Date

    @State private var range: HistoryRange = .oneHour
    @State private var samples: [HistorySample] = []
    @State private var hoverDate: Date?

    var body: some View {
        let agg = HistoryAggregation.aggregate(samples: samples, range: range)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Historique de température")
                    .font(.title3.bold())
                Spacer()
                Picker("Plage", selection: $range) {
                    Text("1 heure").tag(HistoryRange.oneHour)
                    Text("24 heures").tag(HistoryRange.twentyFourHours)
                    Text("7 jours").tag(HistoryRange.sevenDays)
                    Text("30 jours").tag(HistoryRange.thirtyDays)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }

            // Moins de 3 mesures : pas de courbe exploitable.
            if agg.points.count < 2 || agg.measurementCount < 3 {
                emptyState
            } else {
                chart(agg)
                    .frame(height: 220)
                legend(agg)
            }
        }
        .onAppear(perform: load)
        .onChange(of: lastRead) { load() }
        .onChange(of: range) { load() }
        .onChange(of: historyKey) { load() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "thermometer.medium")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Pas encore assez de mesures.")
                .font(.headline)
            Text("Laissez Aman dans la barre des menus pour suivre la température en continu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func chart(_ agg: AggregationResult) -> some View {
        let yMin = Double(max(0, (agg.min ?? 0) - 5))
        let yMax = Double(min(100, (agg.max ?? 0) + 5))
        let hoveredGap = hoverDate.flatMap { d in agg.gaps.first(where: { $0.contains(d) }) }
        let hoveredPoint: AggregatedPoint? = hoveredGap == nil ? hoverDate.flatMap { d in
            agg.points.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) })
        } : nil

        return Chart {
            ForEach(agg.points) { point in
                if range.showsMinMaxBand, let lo = point.minTemperature, let hi = point.maxTemperature {
                    AreaMark(
                        x: .value("Heure", point.date),
                        yStart: .value("Min", lo),
                        yEnd: .value("Max", hi),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(Color.blue.opacity(0.15))
                } else {
                    AreaMark(
                        x: .value("Heure", point.date),
                        y: .value("Temp", point.temperature),
                        series: .value("Segment", point.segment)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .alignsMarkStylesWithPlotArea(true)
                }

                LineMark(
                    x: .value("Heure", point.date),
                    y: .value("Temp", point.temperature),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.blue)
            }

            if let gap = hoveredGap, let d = hoverDate {
                RuleMark(x: .value("Heure", d))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(Color.gray)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: gapTitle(gap), value: "Aucune mesure — Aman n'était pas ouvert")
                    }
            } else if let point = hoveredPoint {
                RuleMark(x: .value("Heure", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(Color.gray)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(title: dateLabel(point.date), value: valueLabel(point))
                    }
            }
        }
        .chartXScale(domain: Date().addingTimeInterval(-range.timeInterval)...Date())
        .chartYScale(domain: yMin...yMax)
        .chartXAxis { AxisMarks(preset: .aligned) }
        .chartYAxis { AxisMarks(preset: .aligned) }
        .chartBackground { proxy in
            // Coupures : bande hachurée très discrète, sans ligne ni remplissage.
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plot = geo[plotAnchor]
                    ForEach(agg.gaps, id: \.self) { gap in
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let plotAnchor = proxy.plotFrame {
                                let x = location.x - geo[plotAnchor].minX
                                hoverDate = proxy.value(atX: x)
                            }
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
        .accessibilityLabel("Courbe de température")
        .accessibilityValue(legendText(agg))
    }

    private func legend(_ agg: AggregationResult) -> some View {
        Text(legendText(agg))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func legendText(_ agg: AggregationResult) -> String {
        var parts: [String] = []
        if let v = agg.min { parts.append("Min \(Formatters.temperature(v))") }
        if let v = agg.average { parts.append("Moyenne \(Formatters.temperature(v))") }
        if let v = agg.max { parts.append("Max \(Formatters.temperature(v))") }
        let n = agg.measurementCount
        parts.append("\(Formatters.integer(UInt64(n))) \(n > 1 ? "mesures" : "mesure")")
        return parts.joined(separator: " · ")
    }

    private func tooltip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .cornerRadius(6)
        .shadow(radius: 2)
    }

    private func dateLabel(_ date: Date) -> String {
        range == .oneHour
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private func gapTitle(_ gap: DateInterval) -> String {
        "\(dateLabel(gap.start)) – \(dateLabel(gap.end))"
    }

    private func valueLabel(_ point: AggregatedPoint) -> String {
        let avg = Formatters.temperature(Int(point.temperature.rounded()))
        if range.showsMinMaxBand, let lo = point.minTemperature, let hi = point.maxTemperature {
            return "\(avg) (min \(Int(lo.rounded())), max \(Int(hi.rounded())))"
        }
        return avg
    }

    private func load() {
        guard let historyKey else {
            samples = []
            return
        }
        let since = Date().addingTimeInterval(-range.timeInterval)
        samples = HistoryStore.shared.samples(for: historyKey, since: since)
    }
}

/// Hachures diagonales qui remplissent le cadre.
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
