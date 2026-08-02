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
        // The five largest rows of `demoAssets`, named identically: the Overview's
        // top-holdings card and the asset detail screen are two views of one
        // portfolio, and a holding that appears in only one of them reads as a
        // bug in whichever the reader looked at second.
        topHoldings: [
            Holding(name: "Family home", value: 385_000, sheet: "Real estate"),
            Holding(name: "US index fund", value: 268_000, sheet: "Investments"),
            Holding(name: "401(k) target date", value: 168_000, sheet: "Investments"),
            Holding(name: "Bitcoin", value: 96_000, sheet: "Crypto"),
            Holding(name: "Total international fund", value: 94_000, sheet: "Investments"),
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
        debts: demoDebts,
        updatedAt: Date().timeIntervalSince1970
    )

    /// The demo book: six sheets, thirteen sections, twenty-five rows.
    ///
    /// Deep enough to exercise every path the asset detail screen has — several
    /// sections under a sheet, several rows under a section, a row with no
    /// section that parks under `OverviewModules.unsortedGroupName`, and a
    /// closed account sitting at zero — while staying spread widely enough for
    /// the composition breakdown to group, rank and fold into "Other".
    ///
    /// The six sheet totals are fixed: Investments 860K, Real estate 450K,
    /// Crypto 130K, Banks 74K, Vehicles 62K and Collectibles 34K, summing to the
    /// snapshot's 1,610,000 asset total. Sections and rows may be reshaped
    /// underneath them freely, but moving a sheet total moves the Sankey's bands
    /// and the composition breakdown's bars, which are asserted against these
    /// figures.
    private static let demoAssets: [PortfolioDetail.Asset] = [
        // Investments — 860,000
        .init(name: "US index fund", value: 268_000, assetClass: "Investment", ticker: "VTI", sheet: "Investments", section: "Taxable"),
        .init(name: "Total international fund", value: 94_000, assetClass: "Investment", ticker: "VXUS", sheet: "Investments", section: "Taxable"),
        .init(name: "Growth fund", value: 84_000, assetClass: "Fund", ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "Brokerage cash sweep", value: 72_000, assetClass: "Cash", ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "Treasury ladder", value: 62_000, assetClass: "Bond", ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "401(k) target date", value: 168_000, assetClass: "Investment", ticker: nil, sheet: "Investments", section: "Retirement"),
        .init(name: "Roth IRA", value: 52_000, assetClass: "Investment", ticker: nil, sheet: "Investments", section: "Retirement"),
        .init(name: "Rollover IRA", value: 20_000, assetClass: "Investment", ticker: nil, sheet: "Investments", section: "Retirement"),
        .init(name: "529 plan", value: 40_000, assetClass: "Investment", ticker: nil, sheet: "Investments", section: "Education"),

        // Real estate — 450,000
        .init(name: "Family home", value: 385_000, assetClass: "Real estate", ticker: nil, sheet: "Real estate", section: "Primary"),
        .init(name: "Duplex share", value: 65_000, assetClass: "Real estate", ticker: nil, sheet: "Real estate", section: "Rental"),

        // Crypto — 130,000
        .init(name: "Bitcoin", value: 96_000, assetClass: "Crypto", ticker: "BTC", sheet: "Crypto", section: "Wallets"),
        .init(name: "Ethereum", value: 28_000, assetClass: "Crypto", ticker: "ETH", sheet: "Crypto", section: "Wallets"),
        .init(name: "Stablecoin balance", value: 6_000, assetClass: "Crypto", ticker: "USDC", sheet: "Crypto", section: "Exchange"),

        // Banks — 74,000
        .init(name: "Checking", value: 31_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Everyday"),
        .init(name: "Joint checking", value: 9_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Everyday"),
        // A closed account Kubera still lists. It is here so the asset table's
        // handling of a zero row is something the demo actually shows.
        .init(name: "Closed student account", value: 0, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Everyday"),
        .init(name: "High-yield savings", value: 26_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Reserve"),
        .init(name: "Emergency fund", value: 8_000, assetClass: "Cash", ticker: nil, sheet: "Banks", section: "Reserve"),

        // Vehicles — 62,000. The motorcycle carries no section, so a filed sheet
        // with an unfiled row inside it is on screen next to a filed one.
        .init(name: "Estate car", value: 27_000, assetClass: "Vehicle", ticker: nil, sheet: "Vehicles", section: "Cars"),
        .init(name: "City runabout", value: 14_000, assetClass: "Vehicle", ticker: nil, sheet: "Vehicles", section: "Cars"),
        .init(name: "Motorcycle", value: 21_000, assetClass: "Vehicle", ticker: nil, sheet: "Vehicles", section: nil),

        // Collectibles — 34,000
        .init(name: "Dive watch", value: 19_000, assetClass: "Collectible", ticker: nil, sheet: "Collectibles", section: "Watches"),
        .init(name: "Field watch", value: 7_500, assetClass: "Collectible", ticker: nil, sheet: "Collectibles", section: "Watches"),
        .init(name: "Camera kit", value: 7_500, assetClass: "Collectible", ticker: nil, sheet: "Collectibles", section: "Misc"),
    ]

    /// The other side of the book: two sheets, four sections, five rows, summing
    /// to the snapshot's 370,000 debt total so the Debts screen totals the same
    /// figure the DEBTS card prints.
    ///
    /// Positive magnitudes, the way Kubera states debts and the way the parser
    /// keeps them — a demo of negative debts would be a demo of a screen the app
    /// does not draw.
    private static let demoDebts: [PortfolioDetail.Asset] = [
        // Loans — 361,000
        .init(name: "Mortgage", value: 300_000, assetClass: "Loan", ticker: nil, sheet: "Loans", section: "Property"),
        .init(name: "Auto loan", value: 41_000, assetClass: "Loan", ticker: nil, sheet: "Loans", section: "Vehicles"),
        .init(name: "Student loan", value: 20_000, assetClass: "Loan", ticker: nil, sheet: "Loans", section: "Education"),

        // Cards — 9,000
        .init(name: "Rewards card", value: 6_500, assetClass: "Credit card", ticker: nil, sheet: "Cards", section: "Everyday"),
        .init(name: "Store card", value: 2_500, assetClass: "Credit card", ticker: nil, sheet: "Cards", section: "Everyday"),
    ]

    /// The CAGR the demo portfolio's growth block prints, standing in for what
    /// Kubera's `get_portfolio_cagr` tool serves.
    ///
    /// Deliberately not the rate `history` implies: that series covers 400 days
    /// of a portfolio Kubera would have been tracking for years, so a served
    /// figure that agreed with it exactly would be showing the demo reader a
    /// coincidence rather than the point — the number on the card is Kubera's,
    /// not one this device worked out.
    static let cagr = PortfolioCAGR(
        netWorth: 14.2,
        investable: 16.8,
        updatedAt: Date().timeIntervalSince1970
    )

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
