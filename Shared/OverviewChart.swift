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

    // MARK: - Scrubbing

    /// Whether the window has enough shape to scrub. One point is a dot: there
    /// is nothing to drag along and no window start to measure a delta from.
    static func isScrubbable(_ points: [ChartPoint]) -> Bool {
        points.count >= 2
    }

    /// The delta the hero retargets to while a finger is on the chart: the
    /// scrubbed point against the **window's first** point, not against today.
    ///
    /// Measuring from the window start is what makes the scrub readable — it
    /// answers "how far had it moved by this date", which is the same question
    /// the resting delta answers, so the number does not change meaning when you
    /// touch the chart. Nil under the same conditions as `change(in:)`.
    static func scrubChange(
        to scrubbed: ChartPoint,
        in points: [ChartPoint]
    ) -> (amount: Double, percent: Double)? {
        guard points.count >= 2, let first = points.first, first.value != 0 else { return nil }
        let amount = scrubbed.value - first.value
        return (amount: amount, percent: amount / first.value * 100)
    }

    /// What a drag over the chart is asking for.
    ///
    /// The chart lives inside the page's vertical `ScrollView`, so a drag has to
    /// prove it means the chart before it is allowed to take over: a gesture
    /// that grabs the touch on contact steals every vertical swipe that starts
    /// on the chart and the page stops scrolling there.
    enum ScrubIntent: Sendable, Equatable {
        /// Hasn't moved far enough to tell — keep watching, change nothing.
        case undecided
        /// Horizontal and past the threshold: the finger is scrubbing.
        case scrub
        /// Vertical: the page is scrolling, and this drag never becomes a scrub.
        case scroll
    }

    /// How far a finger travels before its direction is taken as intent. Small
    /// enough that engaging still feels immediate, large enough that the noise
    /// in a fingertip's first few points doesn't decide.
    static let scrubEngageDistance: Double = 6

    /// Classifies a drag's translation. The dominant axis wins, and an exact tie
    /// reads as a scroll — the page keeping the touch is the safer mistake,
    /// because a missed scrub costs one more swipe while a stolen scroll makes
    /// the screen feel stuck.
    static func intent(
        dx: Double,
        dy: Double,
        threshold: Double = scrubEngageDistance
    ) -> ScrubIntent {
        let horizontal = abs(dx)
        let vertical = abs(dy)
        guard max(horizontal, vertical) >= threshold else { return .undecided }
        return horizontal > vertical ? .scrub : .scroll
    }

    /// Date at a fraction across the window, 0 being the first point and 1 the
    /// last. The fallback for mapping a touch when Swift Charts won't hand back
    /// its own x scale; clamped, so a finger dragged past either edge reads as
    /// that edge rather than extrapolating off the end of the series.
    static func date(atFraction fraction: Double, in points: [ChartPoint]) -> Date? {
        guard let first = points.first, let last = points.last else { return nil }
        let clamped = min(max(fraction, 0), 1)
        return first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) * clamped)
    }

    /// Horizontal center for the scrub tooltip: the touch position, pulled back
    /// far enough that the bubble stays inside the plot. A bubble wider than the
    /// plot centers instead of committing to an edge it would overhang anyway.
    static func tooltipCenter(near x: Double, tooltipWidth: Double, plotWidth: Double) -> Double {
        guard tooltipWidth < plotWidth else { return plotWidth / 2 }
        let half = tooltipWidth / 2
        return min(max(x, half), plotWidth - half)
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
