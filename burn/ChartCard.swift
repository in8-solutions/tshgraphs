import SwiftUI
import Charts

struct ChartCard: View {
    // Line styles
    private static let solidLine = StrokeStyle(lineWidth: 2)
    private static let dashedLine = StrokeStyle(lineWidth: 2, dash: [6, 4])

    // Theme colors
    static let hoursWorkedColor = Color(red: 0.306, green: 0.631, blue: 1.0)       // #4EA1FF
    static let ceilingColor = Color(red: 0.725, green: 0.110, blue: 0.110)         // #B91C1C
    static let threshold75Color = Color(red: 0.961, green: 0.620, blue: 0.043)     // #F59E0B
    static let underBudgetColor = Color.green
    static let overBudgetColor = Color.red

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
    // Monthly breakdown data
    let monthlySeries: [(month: String, value: Double)]?
    let cumulativeActualSeries: [(month: String, value: Double)]?
    let renderChartWidth: CGFloat?
    @State private var hoverIndex: Int? = nil
    @State private var plotAreaLeading: CGFloat = 0
    @State private var plotAreaWidth: CGFloat = 0
    @State private var chartWidth: CGFloat = 0
    @State private var xPositions: [CGFloat] = []

    private struct ChartWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            let next = nextValue()
            if next > 0 { value = next }
        }
    }

    private struct PlotMetrics: Equatable {
        let leading: CGFloat
        let width: CGFloat
        let xPositions: [CGFloat]
    }

    private struct PlotMetricsKey: PreferenceKey {
        static var defaultValue = PlotMetrics(leading: 0, width: 0, xPositions: [])
        static func reduce(value: inout PlotMetrics, nextValue: () -> PlotMetrics) {
            let next = nextValue()
            if next.width > 0 { value = next }
        }
    }

    init(title: String,
         employees: [String],
         series: [(month: String, value: Double)],
         start: Date,
         end: Date,
         projectedStartIndex: Int?,
         ceilingSeries: [Double]? = nil,
         ceiling75Series: [Double]? = nil,
         monthlySeries: [(month: String, value: Double)]? = nil,
         cumulativeActualSeries: [(month: String, value: Double)]? = nil,
         renderChartWidth: CGFloat? = nil) {
        self.title = title
        self.employees = employees
        self.series = series
        self.start = start
        self.end = end
        self.projectedStartIndex = projectedStartIndex
        self.ceilingSeries = ceilingSeries
        self.ceiling75Series = ceiling75Series
        self.monthlySeries = monthlySeries
        self.cumulativeActualSeries = cumulativeActualSeries
        self.renderChartWidth = renderChartWidth
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
                .foregroundStyle(ChartCard.hoursWorkedColor)
                .lineStyle(isProjected ? ChartCard.dashedLine : ChartCard.solidLine)
                LineMark(
                    x: .value("Month", seg.x2),
                    y: .value("Hours", seg.y2),
                    series: .value("seg", seg.id)
                )
                .foregroundStyle(ChartCard.hoursWorkedColor)
                .lineStyle(isProjected ? ChartCard.dashedLine : ChartCard.solidLine)
            }

            // Points
            ForEach(Array(series.enumerated()), id: \.offset) { idx, p in
                PointMark(
                    x: .value("Month", monthLabels[idx]),
                    y: .value("Hours", p.value)
                )
                .foregroundStyle(ChartCard.hoursWorkedColor)
            }

            // Threshold lines
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
                .foregroundStyle(AnyShapeStyle(ChartCard.threshold75Color))
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
                .foregroundStyle(AnyShapeStyle(ChartCard.ceilingColor))
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("PoP:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(shortDate(start)).font(.subheadline)
                    Text("→").font(.subheadline).foregroundStyle(.tertiary)
                    Text(shortDate(end)).font(.subheadline)
                    Text("•").foregroundStyle(.tertiary)
                    Text(hasProjectedData ? "Total Projected:" : "Total:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let p = projectedTotal {
                        Text(p.hoursFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(projectionColor)
                    } else {
                        Text("—").font(.subheadline)
                    }
                    Text("•").foregroundStyle(.tertiary)
                    Text("Ceiling:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let c = ceilingTotal {
                        Text(c.hoursFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Self.ceilingColor)
                    } else {
                        Text("—").font(.subheadline)
                    }
                    Text("•").foregroundStyle(.tertiary)
                    Text("Remaining:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let remaining = remainingHours {
                        Text(remaining.hoursFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(remaining >= 0 ? Self.underBudgetColor : Self.overBudgetColor)
                    } else {
                        Text("—").font(.subheadline)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Actuals Through:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(shortDate(queryStopDate))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if !employees.isEmpty {
                    Text("Employees: " + employees.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Legend
                HStack(spacing: 20) {
                    Spacer()
                    HStack(spacing: 6) {
                        Capsule().stroke(Self.hoursWorkedColor, lineWidth: 3).frame(width: 36, height: 8)
                        Text("Hours Worked").font(.caption).foregroundStyle(ChartCard.hoursWorkedColor)
                    }
                    if let p = projectedStartIndex, p < series.count {
                        HStack(spacing: 6) {
                            Capsule().stroke(Self.hoursWorkedColor, style: StrokeStyle(lineWidth: 3, dash: [6,4])).frame(width: 36, height: 8)
                            Text("Projected").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let caps = ceiling75Series, caps.contains(where: { $0 > 0 }) {
                        HStack(spacing: 6) {
                            Capsule()
                                .stroke(Self.threshold75Color, lineWidth: 3)
                                .frame(width: 36, height: 8)
                            Text("75%")
                                .font(.caption)
                                .foregroundStyle(Self.threshold75Color)
                        }
                    }
                    if let caps = ceilingSeries, caps.contains(where: { $0 > 0 }) {
                        HStack(spacing: 6) {
                            Capsule()
                                .stroke(Self.ceilingColor, lineWidth: 3)
                                .frame(width: 36, height: 8)
                            Text("Ceiling")
                                .font(.caption)
                                .foregroundStyle(Self.ceilingColor)
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
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ChartWidthKey.self, value: geo.size.width)
                    }
                )
                .chartXScale(domain: monthLabels)
                .chartPlotStyle { $0.padding(.trailing, chartPlotTrailingPadding) }
                .padding(.leading, chartLeadingPadding)
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
                                Text(s).foregroundStyle(isProjected ? Color.secondary : ChartCard.hoursWorkedColor)
                            }
                        }
                    }
                }
                .chartYAxisLabel("Cumulative Hours")
                .frame(maxWidth: .infinity)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame: CGRect? = {
                            if #available(macOS 14.0, *) {
                                return proxy.plotFrame.map { geo[$0] }
                            } else {
                                return geo[proxy.plotAreaFrame]
                            }
                        }()
                        let positions = monthLabels.compactMap { proxy.position(forX: $0) }
                        Color.clear
                            .preference(
                                key: PlotMetricsKey.self,
                                value: PlotMetrics(
                                    leading: plotFrame?.minX ?? 0,
                                    width: plotFrame?.width ?? 0,
                                    xPositions: positions
                                )
                            )
                            .onContinuousHover { phase in
                                guard let currentPlotFrame = plotFrame, currentPlotFrame.width > 0 else {
                                    hoverIndex = nil
                                    return
                                }
                                switch phase {
                                case .active(let location):
                                    let xInPlot = location.x - currentPlotFrame.origin.x
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
                .onPreferenceChange(ChartWidthKey.self) { newWidth in
                    if newWidth > 0 { chartWidth = newWidth }
                }
                .onPreferenceChange(PlotMetricsKey.self) { metrics in
                    if metrics.width > 0 {
                        plotAreaLeading = metrics.leading
                        plotAreaWidth = metrics.width
                        xPositions = metrics.xPositions
                    }
                }

                // Monthly data table
                if let monthly = monthlySeries, !monthly.isEmpty {
                    monthlyDataTable
                        .padding(.top, 0)
                        .padding(.bottom, 12)
                }

            }
            .padding()
        }
    }

    // MARK: - Monthly Data Table
    private let labelColumnWidth: CGFloat = 125
    private let labelColumnSpacing: CGFloat = 8
    private let chartPlotTrailingPadding: CGFloat = 36
    private var chartLeadingPadding: CGFloat { labelColumnWidth + labelColumnSpacing }
    private let dataRowHeight: CGFloat = 18

    @ViewBuilder
    private var monthlyDataTable: some View {
        let columnCount = monthLabels.count

        VStack(alignment: .leading, spacing: 2) {
            // Monthly Hours row (gray for projected months)
            if let monthly = monthlySeries, monthly.count == columnCount {
                dataRow(label: "Monthly", values: monthly.map { $0.value }, color: Self.hoursWorkedColor, projectedStartIndex: projectedStartIndex)
            }

            // Cumulative row (gray for projected months)
            if let cumActual = cumulativeActualSeries, cumActual.count == columnCount {
                dataRow(label: "Cumulative", values: cumActual.map { $0.value }, color: Self.hoursWorkedColor.opacity(0.7), projectedStartIndex: projectedStartIndex)
            }

            // Ceiling row
            if let caps = ceilingSeries, caps.count == columnCount, caps.contains(where: { $0 > 0 }) {
                dataRow(label: "Ceiling", values: caps, color: Self.ceilingColor)
            }

            // 75% row
            if let caps75 = ceiling75Series, caps75.count == columnCount, caps75.contains(where: { $0 > 0 }) {
                dataRow(label: "75%", values: caps75, color: Self.threshold75Color)
            }
        }
    }

    private func dataRow(label: String, values: [Double], color: Color, projectedStartIndex: Int? = nil) -> some View {
        ZStack(alignment: .leading) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: labelColumnWidth, alignment: .trailing)
                .padding(.trailing, labelColumnSpacing)
                .frame(height: dataRowHeight, alignment: .center)

            let layout = rowLayout(for: values.count)
            let effectivePlotWidth = layout.totalWidth
            let columnWidths = layout.columnWidths
            let columnLeading = layout.leading
            if effectivePlotWidth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<values.count, id: \.self) { idx in
                        Rectangle()
                            .fill(Color.white.opacity(0.02))
                            .frame(width: columnWidths[idx], height: dataRowHeight)
                    }
                }
                .frame(width: columnWidths.reduce(0, +), alignment: .leading)
                .offset(x: columnLeading)
            }
            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    let isProjected = projectedStartIndex != nil && idx >= projectedStartIndex!
                    Text(String(format: "%.2f", value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isProjected ? .secondary : color)
                        .frame(width: columnWidths[idx], alignment: .center)
                        .frame(height: dataRowHeight, alignment: .center)
                }
            }
            .frame(width: layout.totalWidth, alignment: .leading)
            .offset(x: columnLeading)
        }
        .frame(height: dataRowHeight)
        .padding(.trailing, chartPlotTrailingPadding)
    }

    // MARK: - Totals & Formatting
    private var projectedTotal: Double? {
        series.last?.value
    }
    private var hasProjectedData: Bool {
        if let p = projectedStartIndex {
            return p >= 0 && p < series.count
        }
        return false
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
        return p > c ? Self.overBudgetColor : Self.underBudgetColor
    }
    private var remainingHours: Double? {
        guard let c = ceilingTotal, let p = projectedTotal else { return nil }
        return c - p
    }

    private var queryStopDate: Date {
        if let p = projectedStartIndex, p > 0, p <= series.count {
            if p == series.count { return end }
            let monthKey = series[p - 1].month
            return DateFormatters.yearMonth.date(from: monthKey) ?? end
        }
        return end
    }

    private struct RowLayout {
        let leading: CGFloat
        let totalWidth: CGFloat
        let columnWidths: [CGFloat]
    }

    private func rowLayout(for count: Int) -> RowLayout {
        let fallbackChartWidth = renderChartWidth ?? chartWidth
        let basePlotWidth = plotAreaWidth > 0
            ? plotAreaWidth
            : max(0, fallbackChartWidth - chartLeadingPadding - chartPlotTrailingPadding)
        let baseLeading = plotAreaWidth > 0 ? plotAreaLeading : chartLeadingPadding
        guard count > 0 else { return RowLayout(leading: baseLeading, totalWidth: 0, columnWidths: []) }
        let usePositions = xPositions.count == count && xPositions.count >= 2
        if usePositions {
            let sorted = xPositions
            let gaps = zip(sorted, sorted.dropFirst()).map { $1 - $0 }
            let firstGap = gaps.first ?? 0
            let lastGap = gaps.last ?? 0
            let start = sorted.first.map { $0 - firstGap / 2 } ?? 0
            let end = sorted.last.map { $0 + lastGap / 2 } ?? basePlotWidth
            let midpoints = zip(sorted, sorted.dropFirst()).map { ($0 + $1) / 2.0 }
            let boundaries = [start] + midpoints + [end]
            let widths = zip(boundaries, boundaries.dropFirst()).map { max(0, $1 - $0) }
            return RowLayout(
                leading: plotAreaLeading + (boundaries.first ?? 0),
                totalWidth: widths.reduce(0, +),
                columnWidths: widths
            )
        } else {
            let w = basePlotWidth / CGFloat(count)
            let widths = Array(repeating: w, count: count)
            return RowLayout(leading: baseLeading, totalWidth: basePlotWidth, columnWidths: widths)
        }
    }

    private func shortDate(_ d: Date) -> String {
        DateFormatters.shortDate.string(from: d)
    }
}
