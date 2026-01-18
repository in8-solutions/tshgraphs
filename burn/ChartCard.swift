import SwiftUI
import Charts

struct ChartCard: View {
    // Line styles
    private static let solidLine = StrokeStyle(lineWidth: 2)
    private static let dashedLine = StrokeStyle(lineWidth: 2, dash: [6, 4])

    // Inputs
    let title: String
    let employees: [String]
    let series: [(month: String, value: Double)]
    let start: Date
    let end: Date
    // Optional stepped ceiling series (aligned to series months)
    let ceilingSeries: [Double]?
    let ceiling75Series: [Double]?
    let projectedStartIndex: Int?
    @State private var hoverIndex: Int? = nil

    init(title: String,
         employees: [String],
         series: [(month: String, value: Double)],
         start: Date,
         end: Date,
         projectedStartIndex: Int?,
         ceilingSeries: [Double]? = nil,
         ceiling75Series: [Double]? = nil) {
        self.title = title
        self.employees = employees
        self.series = series
        self.start = start
        self.end = end
        self.projectedStartIndex = projectedStartIndex
        self.ceilingSeries = ceilingSeries
        self.ceiling75Series = ceiling75Series
    }

    // Segment for line drawing
    private struct Segment: Identifiable {
        let id: Int
        let x1: String
        let y1: Double
        let x2: String
        let y2: Double
    }

    // MARK: Helpers
    private func monthYearShort(for monthString: String) -> String {
        guard let date = DateFormatters.yearMonth.date(from: monthString) else { return monthString }
        return DateFormatters.monthYearShort.string(from: date)
    }

    private var monthLabels: [String] {
        series.map { monthYearShort(for: $0.month) }
    }

    private var segments: [Segment] {
        guard series.count >= 2 else { return [] }
        return (0..<(series.count - 1)).map { i in
            let a = series[i]
            let b = series[i + 1]
            return Segment(id: i,
                           x1: monthLabels[i], y1: a.value,
                           x2: monthLabels[i + 1], y2: b.value)
        }
    }

    // Encapsulated chart content
    private struct BurnMarks: ChartContent {
        let segments: [Segment]
        let series: [(month: String, value: Double)]
        let monthLabels: [String]
        let ceilingSeries: [Double]?
        let ceiling75Series: [Double]?
        let hoverIndex: Int?
        let projectedStartIndex: Int?

        var body: some ChartContent {
            // Lines for each segment
            ForEach(segments) { seg in
                let isProjected = {
                    if let p = projectedStartIndex { return seg.id >= max(p - 1, 0) }
                    return false
                }()
                LineMark(
                    x: .value("Month", seg.x1),
                    y: .value("Hours", seg.y1),
                    series: .value("seg", seg.id)
                )
                .foregroundStyle(.blue)
                .lineStyle(isProjected ? ChartCard.dashedLine : ChartCard.solidLine)
                LineMark(
                    x: .value("Month", seg.x2),
                    y: .value("Hours", seg.y2),
                    series: .value("seg", seg.id)
                )
                .foregroundStyle(.blue)
                .lineStyle(isProjected ? ChartCard.dashedLine : ChartCard.solidLine)
            }

            // Points
            ForEach(Array(series.enumerated()), id: \.offset) { idx, p in
                PointMark(
                    x: .value("Month", monthLabels[idx]),
                    y: .value("Hours", p.value)
                )
                .foregroundStyle(.blue)
            }

            // Threshold lines on top: 75% (amber) and Ceiling (red)
            if let caps75 = ceiling75Series, caps75.count == monthLabels.count {
                let pts75 = Array(zip(monthLabels, caps75))
                ForEach(Array(pts75.enumerated()), id: \.0) { _, p in
                    LineMark(
                        x: .value("Month", p.0),
                        y: .value("75% of Ceiling", p.1),
                        series: .value("series", "seventyFive")
                    )
                }
                .interpolationMethod(.linear)
                .foregroundStyle(AnyShapeStyle(Color(hue: 0.14, saturation: 0.95, brightness: 0.95)))
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .zIndex(5)
            }
            if let caps = ceilingSeries, caps.count == monthLabels.count {
                let pts = Array(zip(monthLabels, caps))
                ForEach(Array(pts.enumerated()), id: \.0) { _, p in
                    LineMark(
                        x: .value("Month", p.0),
                        y: .value("Ceiling", p.1),
                        series: .value("series", "ceiling")
                    )
                }
                .interpolationMethod(.linear)
                .foregroundStyle(AnyShapeStyle(Color(red: 1.0, green: 0.22, blue: 0.22)))
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .zIndex(6)
            }

            // Hover marker
            if let hi = hoverIndex, hi >= 0, hi < series.count {
                let p = series[hi]
                let m = monthLabels[hi]
                PointMark(
                    x: .value("Month", m),
                    y: .value("Hours", p.value)
                )
                .symbolSize(120)
                .foregroundStyle(.primary)
                .annotation(position: .top) {
                    Text("\(m): \(p.value, specifier: "%.2f") h")
                        .font(.caption)
                        .padding(6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading) {
                Text(title).font(.headline)
                if !employees.isEmpty {
                    Text("Employees: " + employees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Mini legend

                HStack(spacing: 20) {
                    Spacer()
                    HStack(spacing: 6) {
                        Capsule().stroke(Color.blue, lineWidth: 3).frame(width: 36, height: 8)
                        Text("Hours Worked").font(.caption).foregroundStyle(Color.blue)
                    }
                    if let p = projectedStartIndex, p < series.count {
                        HStack(spacing: 6) {
                            Capsule().stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [6,4])).frame(width: 36, height: 8)
                            Text("Projected").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let caps = ceiling75Series, caps.contains(where: { $0 > 0 }) {
                        HStack(spacing: 6) {
                            Capsule()
                                .stroke(Color.yellow, lineWidth: 3)
                                .frame(width: 36, height: 8)
                            Text("75%")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    if let caps = ceilingSeries, caps.contains(where: { $0 > 0 }) {
                        HStack(spacing: 6) {
                            Capsule()
                                .stroke(Color.red, lineWidth: 3)
                                .frame(width: 36, height: 8)
                            Text("Ceiling")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.bottom, 4)

                Chart {
                    BurnMarks(segments: segments,
                              series: series,
                              monthLabels: monthLabels,
                              ceilingSeries: ceilingSeries,
                              ceiling75Series: ceiling75Series,
                              hoverIndex: hoverIndex,
                              projectedStartIndex: projectedStartIndex)
                }
                .chartXScale(domain: monthLabels)
                .chartPlotStyle { $0.padding(.trailing, 36) }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: monthLabels) { val in
                        if let s = val.as(String.self) {
                            let idx = monthLabels.firstIndex(of: s) ?? 0
                            let projectedStart = projectedStartIndex ?? Int.max
                            let isProjected = idx >= projectedStart
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                Text(s).foregroundStyle(isProjected ? Color.secondary : Color.blue)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Month")
                .chartYAxisLabel("Cumulative Hours")
                .frame(maxWidth: .infinity)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let plotFrame: CGRect
                                    if #available(macOS 14.0, *) {
                                        guard let anchor = proxy.plotFrame else { return hoverIndex = nil }
                                        plotFrame = geo[anchor]
                                    } else {
                                        plotFrame = geo[proxy.plotAreaFrame]
                                    }
                                    let xInPlot = location.x - plotFrame.origin.x
                                    var nearest: (idx: Int, dist: CGFloat)? = nil
                                    for (idx, m) in monthLabels.enumerated() {
                                        if let xPos = proxy.position(forX: m) {
                                            let d = abs(xPos - xInPlot)
                                            if nearest == nil || d < nearest!.dist { nearest = (idx, d) }
                                        }
                                    }
                                    hoverIndex = nearest?.idx
                                case .ended:
                                    hoverIndex = nil
                                }
                            }
                    }
                }
                .chartLegend(.hidden)

                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Projected Total:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let p = projectedTotal {
                        Text(p.hoursFormatted)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(projectionColor)
                    } else {
                        Text("—").font(.footnote)
                    }
                    Divider().frame(height: 12)
                    Text("Ceiling:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let c = ceilingTotal {
                        Text(c.hoursFormatted)
                            .font(.footnote.weight(.semibold))
                    } else {
                        Text("—").font(.footnote)
                    }
                }
                .padding(.top, 2)
            }
            .padding()
        }
    }

    // MARK: - Totals & Formatting
    private var projectedTotal: Double? {
        series.last?.value
    }
    private var ceilingTotal: Double? {
        guard let caps = ceilingSeries, !caps.isEmpty else { return nil }
        // Use the last value aligned to the series length if possible
        let idx = min(caps.count, series.count) - 1
        guard idx >= 0 else { return caps.last }
        return caps[idx]
    }
    private var projectionColor: Color {
        guard let p = projectedTotal, let c = ceilingTotal else { return .primary }
        if p > c * 1.10 { return .red }        // > 10% over
        else if p > c { return .orange }       // 0-10% over
        else { return .green }                 // at or under
    }

    private var footerText: String {
        let pop = "PoP: \(shortDate(start)) → \(shortDate(end))"
        guard let p = projectedStartIndex, p > 0, p <= series.count else { return pop }
        let key = series[p - 1].month
        if let qs = endOfMonth(forMonthKey: key) {
            return pop + " • Query Stop: " + shortDate(qs)
        }
        return pop
    }

    private func endOfMonth(forMonthKey key: String) -> Date? {
        guard let monthDate = DateFormatters.yearMonth.date(from: key) else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        guard let startOfMonth = cal.date(from: comps),
              let days = cal.range(of: .day, in: .month, for: startOfMonth)?.count else { return nil }
        return cal.date(byAdding: .day, value: days - 1, to: startOfMonth)
    }

    private func shortDate(_ d: Date) -> String {
        DateFormatters.shortDate.string(from: d)
    }
}
