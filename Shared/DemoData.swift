import Foundation

/// The synthetic portfolio the welcome screen renders, so first run can show the
/// product instead of describing it.
///
/// Every figure is invented. This repository is public, so nothing here may
/// resemble a real person's balances — and nothing in here is ever written to
/// the App Group caches the widgets read, so a demo number can never surface as
/// if it were the user's own.
///
/// The history series is generated, not random: the wobble comes from the day
/// index through `sin`, so the demo chart draws the same curve on every launch
/// and the tests have something stable to assert.
enum DemoData {
    /// Marks the demo portfolio apart from a fetched one. `PortfolioSnapshot`
    /// has no flag of its own, and the id is the one field guaranteed to be
    /// carried through every cache and view.
    static let portfolioId = "demo-sample"

    static func isDemo(_ snapshot: PortfolioSnapshot) -> Bool {
        snapshot.portfolioId == portfolioId
    }

    // MARK: - Shape of the series

    /// Long enough that the 1Y window is full and ALL reaches past it.
    static let dayCount = 400

    /// The series starts here and ends on `snapshot.netWorth`, so the chart's
    /// last point and the hero number are the same figure.
    static let startNetWorth: Double = 892_000
    static let startDebtTotal: Double = 410_000

    // MARK: - Snapshot

    static let snapshot = PortfolioSnapshot(
        portfolioId: portfolioId,
        portfolioName: "Sample portfolio",
        currency: "USD",
        netWorth: 1_240_000,
        assetTotal: 1_610_000,
        debtTotal: 370_000,
        costBasis: 1_026_000,
        unrealizedGain: 214_000,
        topHoldings: [
            Holding(name: "Index funds", value: 620_000, sheet: "Investments"),
            Holding(name: "Home", value: 450_000, sheet: "Real estate"),
            Holding(name: "Retirement", value: 240_000, sheet: "Investments"),
            Holding(name: "Bitcoin", value: 96_000, sheet: "Crypto"),
            Holding(name: "Cash", value: 74_000, sheet: "Banks"),
        ],
        allocation: ["Investable": 58, "Real estate": 28, "Crypto": 6, "Cash": 5, "Collectibles": 3],
        updatedAt: Date().timeIntervalSince1970
    )

    /// Computed from `history` through the same calculator the app uses, rather
    /// than typed in: the widget previews' 1 DAY and YTD figures then agree with
    /// the delta the hero card reads off the same series, whatever day the demo
    /// is being shown on. The literal is a floor for a series too short to have
    /// references, which 400 daily points never is.
    static let trends = TrendsCalculator.compute(
        series: history,
        currentNetWorth: snapshot.netWorth,
        now: Date(),
        calendar: .current
    ) ?? PortfolioTrends(
        day: PortfolioTrends.Change(amount: 1_000, percent: 0.08),
        year: PortfolioTrends.Change(amount: 248_000, percent: 25.0),
        ytd: PortfolioTrends.Change(amount: 142_000, percent: 12.9),
        qtd: PortfolioTrends.Change(amount: 41_000, percent: 3.4),
        updatedAt: Date().timeIntervalSince1970
    )

    static let comps = MarketComps(
        sp500: 9.4,
        dowJones: 6.1,
        btc: 18.7,
        updatedAt: Date().timeIntervalSince1970
    )

    /// Privacy mode off and compaction on: the defaults, which is what the
    /// widget previews should be showing a new user.
    static let settings = WidgetSettings()

    // MARK: - Detail and profile

    /// The figures Kubera serves only over MCP, so the demo can fill the same
    /// modules the live Overview does — cash on hand, tax estimate, investable,
    /// and the sheet/section hierarchy the composition breakdown groups by.
    ///
    /// Internally consistent on purpose: the asset values sum to the snapshot's
    /// asset total, and `netWorth` is `assetTotal - debtTotal`, so nothing in the
    /// demo contradicts anything else on screen.
    static let detail = PortfolioDetail(
        currency: snapshot.currency,
        netWorth: snapshot.netWorth,
        assetTotal: snapshot.assetTotal,
        debtTotal: snapshot.debtTotal,
        cashOnHand: 74_000,
        estimatedTax: 96_400,
        investableTotal: 1_066_400,
        costBasis: snapshot.costBasis,
        unrealizedGain: snapshot.unrealizedGain,
        assets: demoAssets,
        updatedAt: Date().timeIntervalSince1970
    )

    /// Spread across enough sheets and sections that the composition breakdown
    /// has something to group, rank, and fold into "Other".
    private static let demoAssets: [PortfolioDetail.Asset] = [
        .init(name: "Index funds", value: 430_000, assetClass: "Investment", ticker: "VTI", sheet: "Investments", section: "Taxable"),
        .init(name: "Retirement", value: 240_000, assetClass: "Investment", ticker: nil, sheet: "Investments", section: "Retirement"),
        .init(name: "Growth fund", value: 190_000, assetClass: "Fund", ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "Home", value: 450_000, assetClass: "Real estate", ticker: nil, sheet: "Real estate", section: "Primary"),
        .init(name: "Bitcoin", value: 96_000, assetClass: "Crypto", ticker: "BTC", sheet: "Crypto", section: "Wallets"),
        .init(name: "Ethereum", value: 34_000, assetClass: "Crypto", ticker: "ETH", sheet: "Crypto", section: "Wallets"),
        .init(name: "Checking", value: 48_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Everyday"),
        .init(name: "Savings", value: 26_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Reserve"),
        .init(name: "Car", value: 62_000, assetClass: "Vehicle", ticker: nil, sheet: "Vehicles", section: nil),
        .init(name: "Watch", value: 34_000, assetClass: "Collectible", ticker: nil, sheet: "Collectibles", section: nil),
    ]

    /// A first name, so the greeting has something to use in the demo. Chosen to
    /// be obviously a placeholder rather than anyone's real name.
    static let profile = KuberaProfile(name: "Sam Rivera", email: nil)

    /// Stand-in credentials for the debug demo run, which needs a non-nil value
    /// to get past the connect screen but never talks to Kubera. Deliberately
    /// self-describing rather than key-shaped: nothing here should ever be
    /// mistaken for a real secret, and nothing writes it to the Keychain.
    static let credentials = KuberaCredentials(
        apiKey: "demo-not-a-real-key",
        secret: "demo-not-a-real-secret",
        mcpToken: "demo-not-a-real-token"
    )

    /// The portfolio list, which Settings' picker and the portfolio switcher
    /// both read. Two entries, so a switcher has something to switch between.
    static let portfolios: [PortfolioListItem] = [
        PortfolioListItem(id: portfolioId, name: "Sample portfolio", currency: "USD"),
        PortfolioListItem(id: "demo-sample-2", name: "Family", currency: "USD"),
    ]

    // MARK: - History

    /// The demo series, ending today. Resolved once per process, so every view
    /// that reads it draws the same curve.
    static let history = generateHistory()

    /// `end` is the date of the last point; the series runs back `dayCount` days
    /// from it, one point per day, ascending.
    ///
    /// Growth is exponential from `startNetWorth` to the snapshot's net worth,
    /// with a deterministic wobble laid over it. The wobble is enveloped by
    /// `sin(πt)`, which is zero at both ends — that pins the first point to
    /// `startNetWorth` and the last to the hero number, with no seam.
    static func generateHistory(
        endingOn end: Date = Date(),
        calendar: Calendar = .current
    ) -> [KuberaAPI.HistoryPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let lastDay = calendar.startOfDay(for: end)
        let growth = snapshot.netWorth / startNetWorth

        return (0 ..< dayCount).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - (dayCount - 1), to: lastDay) else {
                return nil
            }
            let t = Double(index) / Double(dayCount - 1)
            let netWorth = startNetWorth * pow(growth, t) * (1 + envelope(t) * wobble(index))
            // Debt amortizes on a straight line — a mortgage plus a car loan
            // paying down, not something that reacts to the markets.
            let debt = startDebtTotal + (snapshot.debtTotal - startDebtTotal) * t
            // Investable is the liquid slice, so it tracks net worth but swings
            // wider: the illiquid half (a home, a car) does not move day to day,
            // which is exactly why the two curves are worth drawing together.
            let investableShare = 0.72 + 0.10 * t
            let investable = netWorth * investableShare * (1 + envelope(t) * wobble(index) * 0.6)

            return KuberaAPI.HistoryPoint(
                date: formatter.string(from: date),
                value: netWorth,
                assetTotal: netWorth + debt,
                debtTotal: debt,
                investibleTotal: investable
            )
        }
    }

    /// Three sine terms at unrelated periods: a slow swing of a few percent, a
    /// weekly-ish ripple, and a little daily jitter. Nothing repeats over 400
    /// days, so the curve never looks stamped out.
    private static func wobble(_ index: Int) -> Double {
        let i = Double(index)
        return 0.030 * sin(i * 0.091)
            + 0.014 * sin(i * 0.37 + 1.1)
            + 0.005 * sin(i * 1.7)
    }

    private static func envelope(_ t: Double) -> Double {
        sin(.pi * t)
    }

    // MARK: - Parsed series

    /// Parsed once, since each parse walks 400 points through a DateFormatter
    /// and the welcome screen re-reads these on every range change.
    static let netWorthPoints = OverviewChart.points(from: history, calendar: .current)
    static let assetPoints = OverviewChart.points(from: history, calendar: .current) { $0.assetTotal }
    static let debtPoints = OverviewChart.points(from: history, calendar: .current) { $0.debtTotal }
    static let investablePoints = OverviewChart.points(from: history, calendar: .current) { $0.investibleTotal }
}
