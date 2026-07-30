import Foundation

/// Arithmetic for the Overview screen's Kubera-parity modules: the 1 DAY /
/// 1 YEAR lines under Assets and Debts, the investable figure that only the
/// history series carries, and the YTD / CAGR numbers in the growth block.
///
/// Foundation-only and pure, exactly like `OverviewChart` — the screen stays
/// layout, and the test bundle compiles this without the app target.
enum OverviewModules {
    /// A change measured against a reference point. `percent` is optional on
    /// purpose: a reference of 0 has no percentage, and printing "0%" there
    /// would state something untrue.
    struct Change: Hashable, Sendable {
        let amount: Double
        let percent: Double?
    }

    /// The two lines Kubera's dashboard prints under Assets and Debts. Either
    /// can be nil — a series that does not reach back a year has no 1-year
    /// change, and "unknown" must not render as "0%".
    struct MetricTrend: Hashable, Sendable {
        let day: Change?
        let year: Change?
    }

    /// One benchmark in the comps row.
    struct Comp: Hashable, Identifiable, Sendable {
        let name: String
        let percent: Double

        var id: String { name }
    }

    /// Days in an average year, leap years included — the divisor for CAGR's
    /// exponent.
    static let daysPerYear = 365.25

    // MARK: - Per-metric trends

    /// The 1 DAY / 1 YEAR pair for one metric.
    ///
    /// References match `TrendsCalculator` exactly — the day compares against
    /// the latest point strictly before today, the year against the latest
    /// point on or before this date last year — so the screen can never
    /// disagree with the widgets about the same number.
    static func trend(
        in points: [ChartPoint],
        current: Double?,
        now: Date,
        calendar: Calendar
    ) -> MetricTrend {
        let today = calendar.startOfDay(for: now)
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)
        return MetricTrend(
            day: change(from: reference(in: points, before: today), to: current),
            year: change(from: yearAgo.flatMap { reference(in: points, onOrBefore: $0) }, to: current)
        )
    }

    /// Growth since the last close of the previous calendar year. Nil when the
    /// series does not reach into last year — a portfolio logged since March
    /// has no year-to-date figure, only a since-March one.
    static func ytdPercent(
        in points: [ChartPoint],
        current: Double?,
        now: Date,
        calendar: Calendar
    ) -> Double? {
        guard let startOfYear = startOfYear(now, calendar: calendar) else { return nil }
        return change(from: reference(in: points, before: startOfYear), to: current)?.percent
    }

    /// Compound annual growth rate over the whole series, as a percent.
    ///
    /// Nil unless the series spans at least `minimumYears`: annualizing a
    /// three-month log produces a rate nobody's portfolio will hold for a year,
    /// and a made-up rate is worse than a missing one.
    static func cagrPercent(in points: [ChartPoint], minimumYears: Double = 1) -> Double? {
        guard let first = points.first, let last = points.last,
              first.value > 0, last.value > 0 else { return nil }

        let years = last.date.timeIntervalSince(first.date) / (daysPerYear * 24 * 60 * 60)
        guard years >= minimumYears else { return nil }
        return (pow(last.value / first.value, 1 / years) - 1) * 100
    }

    // MARK: - Investable

    /// The investable series the history points carry. Kubera's snapshot has no
    /// investable field, so history is the only truthful source for it.
    static func investableSeries(
        from series: [KuberaAPI.HistoryPoint],
        calendar: Calendar
    ) -> [ChartPoint] {
        OverviewChart.points(from: series, calendar: calendar) { $0.investibleTotal }
    }

    /// How old the newest investable point may be before it stops counting as a
    /// current figure.
    ///
    /// This matters because only a server-fetched series carries investable:
    /// `SharedStore.record(historyPointFrom:)` writes `investibleTotal: nil` for
    /// the days the app itself logs, and those on-device points win date
    /// collisions in `mergeLocalHistory`. So the newest investable point can be
    /// months older than the newest net worth point, and printing it beside a
    /// live net worth would misdate it.
    static let investableFreshness: TimeInterval = 7 * 24 * 60 * 60

    /// Investable only when it is recent enough to stand next to today's net
    /// worth. Nil otherwise — a stale figure presented as current is a wrong
    /// number, not a partial one. The chart may still draw the older curve,
    /// which carries its own dates.
    static func currentInvestable(
        in points: [ChartPoint],
        now: Date,
        calendar: Calendar,
        freshness: TimeInterval = investableFreshness
    ) -> Double? {
        // Anchored to the start of today, like `OverviewChart.cutoff`: history
        // points land on midnight, so measuring from a mid-afternoon `now`
        // would quietly shorten the window by most of a day.
        guard let latest = points.last,
              calendar.startOfDay(for: now).timeIntervalSince(latest.date) <= freshness else { return nil }
        return latest.value
    }

    /// Investable, preferring the live figure from `PortfolioDetail` and falling
    /// back to the history series when the detail fetch has not landed or does
    /// not carry it. Nil when neither source can answer.
    static func investable(
        detail: PortfolioDetail?,
        series: [ChartPoint],
        now: Date,
        calendar: Calendar,
        freshness: TimeInterval = investableFreshness
    ) -> Double? {
        if let live = detail?.investableTotal { return live }
        return currentInvestable(in: series, now: now, calendar: calendar, freshness: freshness)
    }

    // MARK: - Composition

    /// One row of the composition breakdown: a sheet or a section, its total,
    /// and its share of everything shown beside it.
    struct CompositionGroup: Hashable, Identifiable, Sendable {
        let name: String
        let value: Double
        /// Share of the grouped total, 0–100 — not share of net worth, which
        /// these rows do not sum to.
        let percent: Double

        var id: String { name }
    }

    /// Where assets with no label at this level land.
    static let unsortedGroupName = "Unsorted"
    /// Where the folded tail lands.
    static let otherGroupName = "Other"

    /// Which of an asset's two labels does the grouping.
    enum CompositionLevel: String, CaseIterable, Identifiable, Sendable {
        case sheet
        case section

        var id: String { rawValue }

        /// Pill label.
        var label: String {
            switch self {
            case .sheet: "SHEET"
            case .section: "SECTION"
            }
        }
    }

    /// Assets aggregated by sheet or section, largest first — the "where is the
    /// money" story a Sankey tells, at a size that fits a phone.
    ///
    /// Rows past `maximumGroups`, and rows under `minimumPercent`, fold into one
    /// trailing "Other" so the list neither runs long nor ends in hairlines.
    /// Assets with no label land in `unsortedName` rather than being dropped —
    /// they are real money, just unfiled.
    static func composition(
        _ assets: [PortfolioDetail.Asset],
        by level: CompositionLevel,
        maximumGroups: Int = 6,
        minimumPercent: Double = 3,
        unsortedName: String = unsortedGroupName,
        otherName: String = otherGroupName
    ) -> [CompositionGroup] {
        var totals: [String: Double] = [:]
        for asset in assets {
            let label = (level == .sheet ? asset.sheet : asset.section)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (label?.isEmpty ?? true) ? unsortedName : label!
            totals[name, default: 0] += asset.value
        }

        // A group summing to zero or less has no share of a positive whole, and
        // showing it as a slice of "where the money is" would misread it.
        var ranked: [(name: String, value: Double)] = []
        for (name, value) in totals where value > 0 {
            ranked.append((name: name, value: value))
        }
        ranked.sort { left, right in
            left.value == right.value ? left.name < right.name : left.value > right.value
        }

        let total = ranked.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var kept: [CompositionGroup] = []
        var remainder: Double = 0
        for (index, group) in ranked.enumerated() {
            let percent = group.value / total * 100
            if index < maximumGroups, percent >= minimumPercent {
                kept.append(CompositionGroup(name: group.name, value: group.value, percent: percent))
            } else {
                remainder += group.value
            }
        }

        guard remainder > 0 else { return kept }
        let remainderPercent = remainder / total * 100
        // An existing "Other" sheet absorbs the remainder rather than gaining a
        // duplicate row, the way `OverviewChart.allocationSegments` does.
        if let index = kept.firstIndex(where: { $0.name == otherName }) {
            kept[index] = CompositionGroup(
                name: otherName,
                value: kept[index].value + remainder,
                percent: kept[index].percent + remainderPercent
            )
        } else {
            kept.append(CompositionGroup(name: otherName, value: remainder, percent: remainderPercent))
        }
        return kept
    }

    /// Whether a level's grouping says anything: one "Unsorted" row is the whole
    /// book with no label on it, which makes a level toggle a dead control.
    static func isLabelled(_ groups: [CompositionGroup]) -> Bool {
        if groups.count > 1 { return true }
        guard let only = groups.first else { return false }
        return only.name != unsortedGroupName
    }

    // MARK: - Comps

    /// The benchmark row, in the order Kubera's dashboard shows it. A benchmark
    /// that failed to fetch drops out instead of showing a zero.
    static func comps(_ comps: MarketComps?) -> [Comp] {
        guard let comps else { return [] }
        var rows: [Comp] = []
        if let value = comps.sp500 { rows.append(Comp(name: "S&P 500", percent: value)) }
        if let value = comps.dowJones { rows.append(Comp(name: "DOW JONES", percent: value)) }
        if let value = comps.btc { rows.append(Comp(name: "BTC", percent: value)) }
        return rows
    }

    // MARK: - Plotting

    /// Y domain covering every series sharing one plot, so net worth and
    /// investable are drawn against the same axis and their gap is readable.
    static func yDomain(_ serieses: [[ChartPoint]]) -> ClosedRange<Double> {
        OverviewChart.yDomain(serieses.flatMap { $0 })
    }

    // MARK: - Helpers

    /// Latest value strictly before the cutoff. Expects ascending input.
    static func reference(in points: [ChartPoint], before cutoff: Date) -> Double? {
        points.last { $0.date < cutoff }?.value
    }

    /// Latest value at or before the cutoff, for anniversary comparisons where
    /// a point landing exactly on the date is the one you want.
    static func reference(in points: [ChartPoint], onOrBefore cutoff: Date) -> Double? {
        points.last { $0.date <= cutoff }?.value
    }

    static func change(from reference: Double?, to current: Double?) -> Change? {
        guard let reference, let current else { return nil }
        let amount = current - reference
        return Change(amount: amount, percent: reference == 0 ? nil : amount / reference * 100)
    }

    private static func startOfYear(_ now: Date, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: calendar.component(.year, from: now),
            month: 1,
            day: 1
        ))
    }
}
