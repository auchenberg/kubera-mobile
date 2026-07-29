import Foundation

/// Point-in-time changes derived from the portfolio history series.
struct PortfolioTrends: Codable {
    struct Change: Codable {
        let amount: Double // current − reference, portfolio currency
        let percent: Double // amount / reference × 100 (0 when reference is 0)
    }

    let day: Change? // vs latest point before today
    let year: Change? // vs point ~1 year ago
    let ytd: Change? // vs last point of the previous calendar year
    let qtd: Change? // vs last point of the previous quarter
    let updatedAt: Double // unix seconds
}

/// Turns a history series into the 1 DAY / 1 YEAR / YTD figures Kubera's
/// dashboard shows. Pure and injectable so the date arithmetic is testable.
enum TrendsCalculator {
    /// series: ascending history points; currentNetWorth: live value; now/calendar injected for testability.
    static func compute(
        series: [KuberaAPI.HistoryPoint],
        currentNetWorth: Double,
        now: Date,
        calendar: Calendar
    ) -> PortfolioTrends? {
        let points = parse(series, calendar: calendar)
        guard !points.isEmpty else { return nil }

        let dayCutoff = calendar.startOfDay(for: now)
        let yearCutoff = calendar.date(byAdding: .year, value: -1, to: now)
        let yearComponent = calendar.component(.year, from: now)
        let monthComponent = calendar.component(.month, from: now)
        let startOfYear = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: yearComponent,
            month: 1,
            day: 1
        ))
        let startOfQuarter = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: yearComponent,
            month: (monthComponent - 1) / 3 * 3 + 1,
            day: 1
        ))

        return PortfolioTrends(
            day: change(from: latest(in: points, before: dayCutoff), to: currentNetWorth),
            year: change(from: yearCutoff.flatMap { latest(in: points, onOrBefore: $0) }, to: currentNetWorth),
            ytd: change(from: startOfYear.flatMap { latest(in: points, before: $0) }, to: currentNetWorth),
            qtd: change(from: startOfQuarter.flatMap { latest(in: points, before: $0) }, to: currentNetWorth),
            updatedAt: now.timeIntervalSince1970
        )
    }

    // MARK: - Helpers

    private struct Point {
        let date: Date
        let value: Double
    }

    /// Drops points without a value or with a date the formatter rejects, and
    /// sorts what is left — the endpoint is documented nowhere, so the caller
    /// cannot rely on it staying ascending.
    private static func parse(_ series: [KuberaAPI.HistoryPoint], calendar: Calendar) -> [Point] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return series
            .compactMap { point in
                guard let value = point.value, let date = formatter.date(from: point.date) else { return nil }
                return Point(date: date, value: value)
            }
            .sorted { $0.date < $1.date }
    }

    private static func latest(in points: [Point], before cutoff: Date) -> Double? {
        points.last { $0.date < cutoff }?.value
    }

    private static func latest(in points: [Point], onOrBefore cutoff: Date) -> Double? {
        points.last { $0.date <= cutoff }?.value
    }

    private static func change(from reference: Double?, to current: Double) -> PortfolioTrends.Change? {
        guard let reference else { return nil }
        let amount = current - reference
        return PortfolioTrends.Change(
            amount: amount,
            percent: reference == 0 ? 0 : amount / reference * 100
        )
    }
}

extension PortfolioTrends {
    static let sample = PortfolioTrends(
        day: Change(amount: 1_240, percent: 0.1),
        year: Change(amount: 240_000, percent: 24.0),
        ytd: Change(amount: 120_000, percent: 10.7),
        qtd: Change(amount: 36_000, percent: 3.1),
        updatedAt: Date().timeIntervalSince1970
    )
}

// MARK: - Local history log

/// The on-device series backing trends when no server history is available —
/// Kubera exposes no history endpoint to API keys (the /v3 guesses 404 and
/// the web app's chartAndCAGR rejects HMAC auth with 401), so the app and the
/// widget record one point per day as they refresh, and trends grow from there.
enum HistoryLog {
    static let cap = 800

    /// Replaces any point with the same date, keeps the series ascending
    /// ("yyyy-MM-dd" sorts lexically), and drops the oldest beyond the cap.
    static func appending(
        _ point: KuberaAPI.HistoryPoint,
        to series: [KuberaAPI.HistoryPoint]
    ) -> [KuberaAPI.HistoryPoint] {
        var merged = series.filter { $0.date != point.date }
        merged.append(point)
        merged.sort { $0.date < $1.date }
        return Array(merged.suffix(cap))
    }
}

extension TrendsCalculator {
    /// Records the snapshot into the local history log, then computes trends
    /// from the best available series: the REST endpoints when one answers,
    /// else Kubera's MCP endpoint, else the log. A server series also backfills
    /// the log so future offline refreshes keep their references. Persists the
    /// result; failures fall back to the last cached trends so callers can
    /// treat this as infallible decoration.
    static func refresh(creds: KuberaCredentials, snapshot: PortfolioSnapshot) async -> PortfolioTrends? {
        SharedStore.record(historyPointFrom: snapshot)

        var series: [KuberaAPI.HistoryPoint]
        if let fetched = try? await KuberaAPI.fetchHistory(creds: creds, portfolioId: snapshot.portfolioId) {
            series = fetched
        } else if let fetched = await KuberaMCP.fetchHistory(creds: creds, portfolioId: snapshot.portfolioId) {
            series = fetched
        } else {
            series = SharedStore.localHistory()
        }
        SharedStore.mergeLocalHistory(series)
        guard let trends = compute(
            series: series,
            currentNetWorth: snapshot.netWorth,
            now: Date(),
            calendar: .current
        ) else {
            return SharedStore.cachedTrends()
        }
        SharedStore.cache(trends: trends)
        return trends
    }
}
