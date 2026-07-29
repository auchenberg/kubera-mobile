import Foundation

/// The windows the Overview chart offers, in the order the pill row shows them.
enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, ytd, year, all

    var id: String { rawValue }

    /// Pill label.
    var label: String {
        switch self {
        case .week: "1W"
        case .month: "1M"
        case .quarter: "3M"
        case .ytd: "YTD"
        case .year: "1Y"
        case .all: "ALL"
        }
    }

    /// Sentence-style tail for the hero delta ("▲ $18,420 +1.5% past month"),
    /// the Origin framing the spec asks for instead of a bare percentage.
    var deltaLabel: String {
        switch self {
        case .week: "past week"
        case .month: "past month"
        case .quarter: "past 3 months"
        case .ytd: "year to date"
        case .year: "past year"
        case .all: "all time"
        }
    }
}

/// One parsed history sample. `Identifiable` by date so Swift Charts can plot
/// the series directly.
struct ChartPoint: Hashable, Identifiable, Sendable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// Chart math for the Overview screen: parsing, range windowing, the Y domain,
/// point lookup for scrubbing, and the deltas the hero and stat cards show.
/// Pure and injectable — the screen holds no arithmetic of its own.
enum OverviewChart {
    /// Whether a stat card's number is an asset-like figure (up is good) or a
    /// debt-like one (down is good).
    enum Metric: Sendable {
        case asset
        case debt
    }

    /// Fraction of the visible span added above and below the curve so the line
    /// never touches the plot edge.
    static let yPadding = 0.06

    /// Gaps longer than this break the line instead of being interpolated
    /// across. Kubera's daily series has holes, and a straight segment over
    /// three missing weeks reads as data that was never recorded.
    static let maxLineGap: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Parsing

    /// Net worth series: drops points without a value or with a date the
    /// formatter rejects, then sorts ascending — the endpoint documents no
    /// ordering guarantee.
    static func points(from series: [KuberaAPI.HistoryPoint], calendar: Calendar) -> [ChartPoint] {
        points(from: series, calendar: calendar) { $0.value }
    }

    /// Same parse against any of the point's figures, so the Assets and Debts
    /// cards can show a range-scoped delta from the same history series.
    static func points(
        from series: [KuberaAPI.HistoryPoint],
        calendar: Calendar,
        value: (KuberaAPI.HistoryPoint) -> Double?
    ) -> [ChartPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return series
            .compactMap { point in
                guard let amount = value(point), let date = formatter.date(from: point.date) else { return nil }
                return ChartPoint(date: date, value: amount)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Range windowing

    /// Oldest date a range keeps, inclusive. Nil for `.all`.
    ///
    /// Anchored to the start of today rather than the current instant: history
    /// points land on midnight, so a cutoff taken from a mid-afternoon `now`
    /// would drop the point on the boundary day and make "1W" six days long.
    static func cutoff(for range: ChartRange, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .week: return calendar.date(byAdding: .day, value: -7, to: today)
        case .month: return calendar.date(byAdding: .month, value: -1, to: today)
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: today)
        case .ytd:
            return calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: calendar.component(.year, from: now),
                month: 1,
                day: 1
            ))
        case .year: return calendar.date(byAdding: .year, value: -1, to: today)
        case .all: return nil
        }
    }

    /// Points inside the range, cutoff inclusive. Expects ascending input and
    /// preserves that order.
    static func filter(
        _ points: [ChartPoint],
        to range: ChartRange,
        now: Date,
        calendar: Calendar
    ) -> [ChartPoint] {
        guard let cutoff = cutoff(for: range, now: now, calendar: calendar) else { return points }
        return points.filter { $0.date >= cutoff }
    }

    // MARK: - Plotting

    /// Never zero-based — a zero-based net worth chart is a flat line at the
    /// top of the plot.
    static func yDomain(_ points: [ChartPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0 ... 1 }

        // A flat series has no span to take a percentage of, so pad against the
        // value itself; the constant floor covers an all-zero series.
        let span = high - low
        let pad = span > 0 ? span * yPadding : max(abs(low) * yPadding, 1)
        return (low - pad) ... (high + pad)
    }

    /// Splits the series wherever the daily history has a hole, so the line
    /// breaks across a gap instead of drawing a slope nobody's portfolio took.
    /// Expects ascending input.
    static func segments(_ points: [ChartPoint], maxGap: TimeInterval = maxLineGap) -> [[ChartPoint]] {
        guard !points.isEmpty else { return [] }

        var runs: [[ChartPoint]] = []
        var current: [ChartPoint] = [points[0]]
        for point in points.dropFirst() {
            if point.date.timeIntervalSince(current[current.count - 1].date) > maxGap {
                runs.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        runs.append(current)
        return runs
    }

    // MARK: - Readouts

    /// Point closest in time to `date`, for scrubbing. Ties go to the earlier
    /// point so a drag between two samples reads as the one already passed.
    static func nearest(to date: Date, in points: [ChartPoint]) -> ChartPoint? {
        var best: ChartPoint?
        var bestDistance = Double.infinity
        for point in points {
            let distance = abs(point.date.timeIntervalSince(date))
            if distance < bestDistance {
                best = point
                bestDistance = distance
            }
        }
        return best
    }

    /// First versus last point of the window. Nil when the window is too short
    /// to have a change, or when the reference is 0 and a percentage would be
    /// meaningless.
    static func change(in points: [ChartPoint]) -> (amount: Double, percent: Double)? {
        guard points.count >= 2, let first = points.first, let last = points.last, first.value != 0 else {
            return nil
        }
        let amount = last.value - first.value
        return (amount: amount, percent: amount / first.value * 100)
    }

    /// Whether a change should read as good news. A shrinking debt is good, so
    /// color follows favorability rather than the sign of the number — the trap
    /// the naive implementation falls into. No change is not good news.
    static func isFavorable(_ amount: Double, metric: Metric) -> Bool {
        switch metric {
        case .asset: amount > 0
        case .debt: amount < 0
        }
    }

    // MARK: - Allocation

    /// One slice of the allocation bar.
    struct AllocationSegment: Hashable, Identifiable, Sendable {
        let name: String
        let percent: Double

        var id: String { name }
    }

    /// Allocation as bar segments: largest first, with everything under
    /// `minimumPercent` folded into one trailing "Other" so the bar doesn't end
    /// in a row of hairlines. Names are the tiebreak, so the order is stable
    /// across refreshes.
    static func allocationSegments(
        _ allocation: [String: Double],
        minimumPercent: Double = 3,
        otherName: String = "Other"
    ) -> [AllocationSegment] {
        var ranked: [AllocationSegment] = []
        for (name, percent) in allocation where percent > 0 {
            ranked.append(AllocationSegment(name: name, percent: percent))
        }
        ranked.sort { left, right in
            left.percent == right.percent ? left.name < right.name : left.percent > right.percent
        }

        var kept: [AllocationSegment] = []
        var remainder: Double = 0
        for segment in ranked {
            if segment.percent >= minimumPercent {
                kept.append(segment)
            } else {
                remainder += segment.percent
            }
        }

        guard remainder > 0 else { return kept }
        // An existing "Other" class absorbs the remainder rather than gaining a
        // duplicate legend entry.
        if let index = kept.firstIndex(where: { $0.name == otherName }) {
            kept[index] = AllocationSegment(name: otherName, percent: kept[index].percent + remainder)
        } else {
            kept.append(AllocationSegment(name: otherName, percent: remainder))
        }
        return kept
    }
}
