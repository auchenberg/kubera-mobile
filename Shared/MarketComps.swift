import Foundation

/// YTD growth of the market benchmarks Kubera's dashboard compares against.
/// Every figure is optional: one benchmark going missing must not cost the
/// others their row.
struct MarketComps: Codable {
    let sp500: Double? // percent, e.g. 8.2
    let dowJones: Double?
    let btc: Double?
    let updatedAt: Double // unix seconds

    var isEmpty: Bool {
        sp500 == nil && dowJones == nil && btc == nil
    }
}

/// Year-to-date math over a daily close series. Pure and injectable so the
/// date arithmetic is testable without touching the network.
enum MarketCompsCalculator {
    /// timestamps/closes are parallel arrays as Yahoo returns them (closes has
    /// nulls on days a symbol did not trade). Reference is the latest close
    /// strictly before Jan 1 of now's year, current the latest close overall;
    /// nil when either is missing or the reference is 0.
    static func ytdPercent(
        timestamps: [Int],
        closes: [Double?],
        now: Date,
        calendar: Calendar
    ) -> Double? {
        let startOfYear = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: calendar.component(.year, from: now),
            month: 1,
            day: 1
        ))
        guard let startOfYear else { return nil }
        let startSeconds = Int(startOfYear.timeIntervalSince1970)

        // Sorted defensively: ascending order is a convention of the endpoint,
        // not a guarantee. zip drops any mismatch in the two array lengths.
        let points = zip(timestamps, closes)
            .compactMap { pair -> (time: Int, close: Double)? in
                guard let close = pair.1 else { return nil }
                return (time: pair.0, close: close)
            }
            .sorted { $0.time < $1.time }

        guard let current = points.last?.close,
              let reference = points.last(where: { $0.time < startSeconds })?.close,
              reference != 0 else { return nil }
        return (current - reference) / reference * 100
    }
}

/// Reads daily closes from Yahoo's public chart API — no auth and no key, and
/// it carries indices and crypto under one response shape.
enum MarketCompsFetcher {
    /// The benchmarks, in the order the dashboard shows them. Adding a comp is
    /// one case here plus one field on MarketComps.
    private enum Benchmark: String {
        case sp500 = "^GSPC"
        case dowJones = "^DJI"
        case btc = "BTC-USD"
    }

    /// Each benchmark fails independently into a nil slot; nil comes back only
    /// when all three fail, so callers can cache whatever they get.
    static func fetch(now: Date = Date(), calendar: Calendar = .current) async -> MarketComps? {
        async let sp500 = ytdPercent(for: .sp500, now: now, calendar: calendar)
        async let dowJones = ytdPercent(for: .dowJones, now: now, calendar: calendar)
        async let btc = ytdPercent(for: .btc, now: now, calendar: calendar)

        let comps = await MarketComps(
            sp500: sp500,
            dowJones: dowJones,
            btc: btc,
            updatedAt: now.timeIntervalSince1970
        )
        return comps.isEmpty ? nil : comps
    }

    // MARK: - Response model

    private struct ChartResponse: Decodable {
        let chart: Chart?

        struct Chart: Decodable {
            let result: [ChartResult]?
        }

        struct ChartResult: Decodable {
            let timestamp: [Int]?
            let indicators: Indicators?
        }

        struct Indicators: Decodable {
            let quote: [Quote]?
        }

        struct Quote: Decodable {
            let close: [Double?]? // nulls appear on untraded days
        }
    }

    // MARK: - Networking

    private static func ytdPercent(for benchmark: Benchmark, now: Date, calendar: Calendar) async -> Double? {
        guard let series = await fetchSeries(benchmark) else { return nil }
        return MarketCompsCalculator.ytdPercent(
            timestamps: series.timestamps,
            closes: series.closes,
            now: now,
            calendar: calendar
        )
    }

    private static func fetchSeries(_ benchmark: Benchmark) async -> (timestamps: [Int], closes: [Double?])? {
        // The index symbols start with "^", which has to reach Yahoo as %5E.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let symbol = benchmark.rawValue.addingPercentEncoding(withAllowedCharacters: unreserved),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=1y&interval=1d")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        // Yahoo answers the default URLSession agent with 403/429 often enough
        // to matter; a browser-ish agent gets served.
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let response = try? await URLSession.shared.data(for: request) else { return nil }
        guard let http = response.1 as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(ChartResponse.self, from: response.0).chart?.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else { return nil }

        return (timestamps: timestamps, closes: closes)
    }
}

extension MarketComps {
    static let sample = MarketComps(
        sp500: 8,
        dowJones: 9,
        btc: -27,
        updatedAt: Date().timeIntervalSince1970
    )
}

extension MarketCompsFetcher {
    /// The cache policy the app and the widget provider share: benchmarks move
    /// slowly and Yahoo is the least reliable dependency, so serve the cache
    /// while it is fresh and fall back to the stale copy when a fetch fails.
    static func cachedOrFresh(maxAge: TimeInterval = 4 * 60 * 60) async -> MarketComps? {
        let cached = SharedStore.cachedMarketComps()
        if let cached, Date().timeIntervalSince1970 - cached.updatedAt < maxAge {
            return cached
        }
        guard let fresh = await fetch() else { return cached }
        SharedStore.cache(marketComps: fresh)
        return fresh
    }
}
