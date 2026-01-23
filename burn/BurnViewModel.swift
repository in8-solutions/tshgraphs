import Foundation
import SwiftUI

enum Route {
    case chart
    case manageCeiling
}

// Cached chart data for a job
private struct ChartCache {
    let cumulativeSeries: [(month: String, value: Double)]
    let monthlySeries: [(month: String, value: Double)]
    let cumulativeActualSeries: [(month: String, value: Double)]
    let employeeNames: [String]
    let projectedStartIndex: Int?
    let ceilingSeries: [Double]?
    let ceiling75Series: [Double]?
    let endDate: Date
}

@MainActor
final class BurnViewModel: ObservableObject {
    // Inputs
    @Published var jobTree: [JobNode] = []
    @Published var selectedJobId: Int? {
        didSet {
            // Save current chart to cache before switching
            if let oldId = oldValue, !cumulativeSeries.isEmpty {
                saveChartToCache(for: oldId)
            }

            // If we are not on Manage Ceiling or we don't have unsaved edits,
            // hydrate from store automatically so the chart screen enables Generate.
            if route != .manageCeiling || !isDirty {
                hydrateFromStore(for: selectedJobId)
                isDirty = false
            }

            // Try to restore chart from cache, otherwise clear it
            if let newId = selectedJobId, let cached = chartCache[newId] {
                restoreChartFromCache(cached)
            } else {
                clearChart()
            }
        }
    }
    var selectedJobName: String? {
        guard let id = selectedJobId else { return nil }
        return jobcodesById[id]?.name
    }
    @Published var startDate: Date = {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        return cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
    }()

    @Published var endDate: Date = {
        let cal = Calendar.current
        let now = Date()
        // Start of current month, then subtract 1 day → last day of previous month
        if let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
           let lastDayPrevMonth = cal.date(byAdding: .day, value: -1, to: startOfThisMonth) {
            return lastDayPrevMonth
        }
        return now
    }()

    @Published var popStartDate: Date? = nil
    @Published var popEndDate: Date? = nil

    // Routing & ceiling management state
    @Published var route: Route = .chart
    @Published var ceilingReleases: [CeilingRelease] = []
    @Published var isDirty: Bool = false
    @Published var showUnsavedConfirm: Bool = false
    private var pendingRoute: Route? = nil
    private var pendingJobIdChange: Int? = nil

    // Outputs
    @Published var cumulativeSeries: [(month: String, value: Double)] = []
    @Published var monthlySeries: [(month: String, value: Double)] = []
    @Published var cumulativeActualSeries: [(month: String, value: Double)] = []
    @Published var alertTitle: String?
    @Published var alertMessage: String?
    @Published var isLoading: Bool = false
    @Published var projectedStartIndex: Int? = nil

    // Optional per-month ceiling thresholds (aligned to cumulativeSeries months)
    @Published var ceilingSeries: [Double]? = nil
    @Published var ceiling75Series: [Double]? = nil

    // Data cache
    private var jobcodesById: [Int: JobCode] = [:]
    private var usersById: [Int: User] = [:]
    @Published var employeeNames: [String] = []
    private var api: APIClient?
    private var chartCache: [Int: ChartCache] = [:]

    /// Job IDs that have cached/generated charts
    var jobsWithCharts: Set<Int> {
        Set(chartCache.keys)
    }

    func loadConfigAndJobs() async {
        do {
            let config = try await Self.loadConfig()
            self.api = try APIClient(config: config)
            async let codesTask = api!.fetchJobCodes()
            async let usersTask = api!.fetchUsers()
            let (codes, users) = try await (codesTask, usersTask)
            self.jobcodesById = codes
            self.usersById = users
            self.jobTree = Self.buildTree(from: codes)
        } catch {
            self.alertTitle = "Error"
            self.alertMessage = "Failed to load config or job codes: \(error.localizedDescription)"
        }
    }

    // MARK: - Ceiling navigation & persistence
    func goToManageCeiling() {
        route = .manageCeiling
        hydrateFromStore(for: selectedJobId)
        isDirty = false
    }

    func requestRouteChange(to newRoute: Route) {
        guard isDirty else { route = newRoute; return }
        pendingRoute = newRoute
        showUnsavedConfirm = true
    }

    func requestJobChange(to newJobId: Int?) {
        // If we're on manage screen and have unsaved edits, confirm first
        guard route == .manageCeiling, isDirty else {
            selectedJobId = newJobId
            hydrateFromStore(for: newJobId)
            isDirty = false
            return
        }
        pendingJobIdChange = newJobId
        showUnsavedConfirm = true
    }

    func saveCeiling() {
        guard let id = selectedJobId else { return }
        let sorted = ceilingReleases.sorted { $0.date < $1.date }
        do {
            let record = CeilingRecord(popStart: popStartDate, popEnd: popEndDate, releases: sorted)
            try CeilingStore.saveRecord(jobId: id, record: record)
            ceilingReleases = sorted
            isDirty = false
            alertTitle = "Success"; alertMessage = "Ceiling saved."
            recomputeCeilingSeriesIfPossible()
        } catch {
            alertTitle = "Error"; alertMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    func discardEdits() {
        isDirty = false
        hydrateFromStore(for: selectedJobId)
    }

    func confirmSaveThenProceed() { saveCeiling(); proceedAfterDecision() }
    func confirmDiscardThenProceed() { discardEdits(); proceedAfterDecision() }
    func cancelProceed() { pendingRoute = nil; pendingJobIdChange = nil; showUnsavedConfirm = false }

    private func proceedAfterDecision() {
        if let r = pendingRoute { route = r; pendingRoute = nil }
        if let jid = pendingJobIdChange {
            selectedJobId = jid
            hydrateFromStore(for: jid)
            pendingJobIdChange = nil
        }
        showUnsavedConfirm = false
    }

    func generateChart() async {
        // Always show progress while we prep
        isLoading = true
        defer { isLoading = false }

        // Ensure we are on the chart screen
        route = .chart

        // Ensure API is initialized; try to load config/jobs if needed
        if self.api == nil {
            await loadConfigAndJobs()
        }
        guard let api = self.api else {
            alertTitle = "Error"
            alertMessage = "Configuration not loaded. Make sure config.json is in the app bundle and try again."
            return
        }
        guard let jobId = selectedJobId else {
            alertTitle = "Error"
            alertMessage = "Select a job first"
            return
        }
        // Ensure we have ceiling releases and PoP dates loaded for this job so thresholds can render
        if ceilingReleases.isEmpty {
            hydrateFromStore(for: jobId)
        }

        // Require PoP dates
        guard let popStart = popStartDate, let popEnd = popEndDate, popStart <= popEnd else {
            alertTitle = "Missing PoP"; alertMessage = "Set PoP Start and End on Manage Ceiling before generating a chart."; return
        }
        // Query Stop must not be before PoP Start
        guard endDate >= popStart else {
            alertTitle = "Invalid Range"; alertMessage = "Query Stop occurs before PoP Start. Adjust Query Stop or PoP dates."; return
        }

        // Normalize dates to start of day for consistent comparisons
        let cal = Calendar.current
        let popEndDay = cal.startOfDay(for: popEnd)
        let endDateDay = cal.startOfDay(for: endDate)
        let hasProjection = popEndDay > endDateDay

        // Build month buckets
        let months = Self.monthKeys(from: popStart, to: endDate)
        var hoursDict: [String: Double] = Dictionary(uniqueKeysWithValues: months.map { ($0, 0.0) })
        var usedUserIds = Set<Int>()

        // Cover all months up to the later of endDate or popEndDate
        let overallEnd = max(endDateDay, popEndDay)
        let allMonths = Self.monthKeys(from: popStart, to: overallEnd)
        for m in allMonths where hoursDict[m] == nil { hoursDict[m] = 0 }

        // Query month-by-month
        var cur = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: popStart))!
        // Use month key comparison to avoid timezone issues with date comparison
        let endMonthKey = Self.keyFor(date: endDate)

        do {
            while Self.keyFor(date: cur) <= endMonthKey {
                let monthStart = Self.monthStart(cur)
                let monthEnd = Self.monthEnd(cur)
                let rangeStart = max(monthStart, popStart)
                let rangeEnd = min(monthEnd, endDate)

                let entries = try await api.fetchTimesheets(start: rangeStart, end: rangeEnd, jobcodeIDs: [jobId])
                entries.forEach { usedUserIds.insert($0.user_id) }
                let totalHours = entries
                    .map { $0.duration / 3600.0 }
                    .reduce(0, +)
                let key = Self.keyFor(date: cur)
                hoursDict[key, default: 0] += totalHours

                cur = Calendar.current.date(byAdding: .month, value: 1, to: cur)!
            }

            // Add projections if PoP extends beyond query stop
            if hasProjection {
                let dayAfterEnd = cal.date(byAdding: .day, value: 1, to: endDateDay) ?? endDateDay
                var curMonth = cal.date(from: cal.dateComponents([.year, .month], from: dayAfterEnd))!
                let lastMonth = cal.date(from: cal.dateComponents([.year, .month], from: popEnd))!
                while curMonth <= lastMonth {
                    let mStart = Self.monthStart(curMonth)
                    let mEnd = Self.monthEnd(curMonth)
                    let projStart = max(mStart, dayAfterEnd)
                    let projEnd = min(mEnd, popEnd)
                    if projStart <= projEnd {
                        let workDays = Self.workingDays(from: projStart, to: projEnd)
                        let hours = Double(workDays * 8)
                        let key = Self.keyFor(date: curMonth)
                        hoursDict[key, default: 0] += hours
                    }
                    curMonth = cal.date(byAdding: .month, value: 1, to: curMonth)!
                }
            }

            // Build cumulative series using allMonths, and record projectedStartIndex
            var running = 0.0
            let dayAfterEnd = cal.date(byAdding: .day, value: 1, to: endDateDay) ?? endDateDay
            let projStartKey = Self.keyFor(date: cal.date(from: cal.dateComponents([.year, .month], from: dayAfterEnd))!)
            var projIdx: Int? = nil
            var monthlyData: [(month: String, value: Double)] = []
            var cumulativeActualData: [(month: String, value: Double)] = []

            cumulativeSeries = allMonths.enumerated().map { (idx, m) in
                // Mark projection start index for chart styling
                // A month is projected if it's the month containing the first projected day (dayAfterEnd) or later
                let isProjectionStart = m >= projStartKey
                if projIdx == nil && isProjectionStart && hasProjection { projIdx = idx }
                let monthHours = hoursDict[m, default: 0]
                running += monthHours

                // For monthly series: include both actual and projected hours
                monthlyData.append((m, monthHours))

                // For cumulative: running total including projected
                cumulativeActualData.append((m, running))

                return (m, running)
            }
            self.projectedStartIndex = projIdx
            self.monthlySeries = monthlyData
            self.cumulativeActualSeries = cumulativeActualData
            let names: [String] = usedUserIds.compactMap { uid in
                if let u = usersById[uid] {
                    if let n = u.name, !n.isEmpty { return n }
                    let fn = u.first_name ?? ""
                    let ln = u.last_name ?? ""
                    let full = (fn + " " + ln).trimmingCharacters(in: .whitespaces)
                    return full.isEmpty ? nil : full
                }
                return nil
            }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            self.employeeNames = names

            // Update ceiling series to match the freshly built months
            self.recomputeCeilingSeriesIfPossible()

            // Cache the generated chart
            saveChartToCache(for: jobId)
        } catch {
            alertTitle = "Error"
            alertMessage = "Failed to generate chart: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers
    private static func nthWeekday(of weekday: Int, inMonth month: Int, year: Int, n: Int) -> Date? {
        var comps = DateComponents(year: year, month: month)
        comps.weekday = weekday
        comps.weekdayOrdinal = n
        let cal = Calendar.current
        return cal.date(from: comps).map { cal.startOfDay(for: $0) }
    }

    private static func lastWeekday(of weekday: Int, inMonth month: Int, year: Int) -> Date? {
        let cal = Calendar.current
        let comps = DateComponents(year: year, month: month + 1, day: 0)
        guard let lastDay = cal.date(from: comps) else { return nil }
        let lastWeekday = cal.component(.weekday, from: lastDay)
        let diff = (lastWeekday - weekday + 7) % 7
        return cal.date(byAdding: .day, value: -diff, to: lastDay).map { cal.startOfDay(for: $0) }
    }

    private static func observedDate(for date: Date) -> Date {
        let cal = Calendar.current
        let dow = cal.component(.weekday, from: date)
        if dow == 1 { // Sunday -> Monday
            return cal.date(byAdding: .day, value: 1, to: date).map { cal.startOfDay(for: $0) } ?? date
        } else if dow == 7 { // Saturday -> Friday
            return cal.date(byAdding: .day, value: -1, to: date).map { cal.startOfDay(for: $0) } ?? date
        }
        return cal.startOfDay(for: date)
    }

    private static func federalHolidays(for year: Int) -> Set<Date> {
        let cal = Calendar.current
        func fixed(_ month: Int, _ day: Int) -> Date? {
            cal.date(from: DateComponents(year: year, month: month, day: day)).map { cal.startOfDay(for: $0) }
        }
        var dates: [Date] = []
        // Fixed-date (observed)
        if let d = fixed(1, 1) { dates.append(observedDate(for: d)) }      // New Year’s Day
        if let d = fixed(6, 19) { dates.append(observedDate(for: d)) }     // Juneteenth
        if let d = fixed(7, 4) { dates.append(observedDate(for: d)) }      // Independence Day
        if let d = fixed(11, 11) { dates.append(observedDate(for: d)) }    // Veterans Day
        if let d = fixed(12, 25) { dates.append(observedDate(for: d)) }    // Christmas
        // Floating
        if let d = nthWeekday(of: 2, inMonth: 1, year: year, n: 3) { dates.append(d) }      // MLK Day (3rd Mon Jan)
        if let d = nthWeekday(of: 2, inMonth: 2, year: year, n: 3) { dates.append(d) }      // Presidents Day (3rd Mon Feb)
        if let d = lastWeekday(of: 2, inMonth: 5, year: year) { dates.append(d) }            // Memorial Day (last Mon May)
        if let d = nthWeekday(of: 2, inMonth: 9, year: year, n: 1) { dates.append(d) }      // Labor Day (1st Mon Sep)
        if let d = nthWeekday(of: 2, inMonth: 10, year: year, n: 2) { dates.append(d) }     // Columbus Day (2nd Mon Oct)
        if let d = nthWeekday(of: 5, inMonth: 11, year: year, n: 4) { dates.append(d) }     // Thanksgiving (4th Thu Nov)
        return Set(dates.map { cal.startOfDay(for: $0) })
    }

    private static func workingDays(from start: Date, to end: Date) -> Int {
        let cal = Calendar.current
        guard start <= end else { return 0 }
        var count = 0
        var cur = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        var holidayCache: [Int: Set<Date>] = [:]
        while cur <= last {
            let wd = cal.component(.weekday, from: cur)
            if wd != 1 && wd != 7 { // Mon–Fri
                let y = cal.component(.year, from: cur)
                if holidayCache[y] == nil { holidayCache[y] = federalHolidays(for: y) }
                if !(holidayCache[y]!.contains(cur)) { count += 1 }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = cal.startOfDay(for: next)
        }
        return count
    }

    private static func loadConfig() async throws -> Config {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json") else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "config.json not found in bundle"]) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    private static func buildTree(from map: [Int: JobCode]) -> [JobNode] {
        // Group by parent
        var childrenByParent: [Int?: [JobCode]] = [:]
        for jc in map.values { childrenByParent[jc.parent_id, default: []].append(jc) }
        func makeChildren(parent: Int?) -> [JobNode] {
            let kids = (childrenByParent[parent] ?? []).sorted { $0.name.lowercased() < $1.name.lowercased() }
            return kids.map { jc in
                JobNode(id: jc.id, name: jc.name, children: makeChildren(parent: jc.id))
            }
        }
        // Roots may be nil or 0
        return makeChildren(parent: nil) + makeChildren(parent: 0)
    }

    private static func monthStart(_ date: Date) -> Date {
        var comp = Calendar.current.dateComponents([.year, .month], from: date)
        comp.day = 1
        return Calendar.current.date(from: comp)!
    }

    private static func monthEnd(_ date: Date) -> Date {
        if let next = Calendar.current.date(byAdding: .month, value: 1, to: monthStart(date)) {
            return Calendar.current.date(byAdding: .day, value: -1, to: next)!
        }
        return date
    }

    private static func keyFor(date: Date) -> String {
        DateFormatters.yearMonth.string(from: date)
    }

    private static func monthKeys(from start: Date, to end: Date) -> [String] {
        var keys: [String] = []
        var cur = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: start))!
        let endAnchor = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: end))!
        while cur <= endAnchor {
            keys.append(keyFor(date: cur))
            cur = Calendar.current.date(byAdding: .month, value: 1, to: cur)!
        }
        return keys
    }

    // Recompute per-month ceiling values aligned to cumulativeSeries months
    func recomputeCeilingSeriesIfPossible() {
        let monthKeys = cumulativeSeries.map { $0.month }
        guard !monthKeys.isEmpty else { ceilingSeries = nil; ceiling75Series = nil; return }
        recomputeCeilingSeries(for: monthKeys)
    }

    func recomputeCeilingSeries(for monthKeys: [String]) {
        guard selectedJobId != nil else { ceilingSeries = nil; ceiling75Series = nil; return }
        let cal = Calendar.current
        // Normalize and sort release dates to local start-of-day to avoid TZ drift and ensure accumulation order
        let releases = ceilingReleases
            .map { CeilingRelease(id: $0.id, date: cal.startOfDay(for: $0.date), hours: $0.hours, note: $0.note) }
            .sorted { $0.date < $1.date }
        if releases.isEmpty { ceilingSeries = nil; ceiling75Series = nil; return }
        var result: [Double] = []
        var runningTotal = 0.0
        var releaseIdx = 0
        let n = releases.count
        // For each month, advance through releases whose date < startOfNextMonth
        for key in monthKeys {
            guard let nextMonthStart = Self.startOfNextMonthForMonthKey(key) else {
                // If key is malformed, repeat last value
                result.append(result.last ?? 0)
                continue
            }
            // Advance releaseIdx and accumulate for releases before nextMonthStart
            while releaseIdx < n, releases[releaseIdx].date < nextMonthStart {
                runningTotal += releases[releaseIdx].hours
                releaseIdx += 1
            }
            result.append(runningTotal)
        }
        if result.allSatisfy({ $0 == 0 }) {
            ceilingSeries = nil
            ceiling75Series = nil
        } else {
            ceilingSeries = result
            ceiling75Series = result.map { $0 * 0.75 }
        }
    }

    private static func startOfNextMonthForMonthKey(_ key: String) -> Date? {
        // key format: "yyyy-MM"
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let cal = Calendar.current
        let comps = DateComponents(year: y, month: m, day: 1)
        guard let first = cal.date(from: comps) else { return nil }
        // Start of next month
        return cal.date(byAdding: .month, value: 1, to: first)
    }
    private func hydrateFromStore(for id: Int?) {
        if let id = id {
            let rec = try? CeilingStore.loadRecord(jobId: id)
            self.ceilingReleases = rec?.releases ?? []
            self.popStartDate = rec?.popStart
            self.popEndDate = rec?.popEnd
        } else {
            self.ceilingReleases = []
            self.popStartDate = nil
            self.popEndDate = nil
        }
    }

    // MARK: - Chart Cache
    private func saveChartToCache(for jobId: Int) {
        chartCache[jobId] = ChartCache(
            cumulativeSeries: cumulativeSeries,
            monthlySeries: monthlySeries,
            cumulativeActualSeries: cumulativeActualSeries,
            employeeNames: employeeNames,
            projectedStartIndex: projectedStartIndex,
            ceilingSeries: ceilingSeries,
            ceiling75Series: ceiling75Series,
            endDate: endDate
        )
    }

    private func restoreChartFromCache(_ cache: ChartCache) {
        cumulativeSeries = cache.cumulativeSeries
        monthlySeries = cache.monthlySeries
        cumulativeActualSeries = cache.cumulativeActualSeries
        employeeNames = cache.employeeNames
        projectedStartIndex = cache.projectedStartIndex
        ceilingSeries = cache.ceilingSeries
        ceiling75Series = cache.ceiling75Series
        endDate = cache.endDate
    }

    private func clearChart() {
        cumulativeSeries = []
        monthlySeries = []
        cumulativeActualSeries = []
        employeeNames = []
        projectedStartIndex = nil
        ceilingSeries = nil
        ceiling75Series = nil
    }
}
