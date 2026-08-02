import XCTest

/// The demo portfolio is what a new user sees before they connect anything, so
/// it has to be stable (same curve on every launch) and internally consistent
/// (the totals and the deltas agree with each other). Every figure under test is
/// synthetic.
final class DemoDataTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private lazy var end = day("2026-07-29")

    private func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    // MARK: - Determinism

    /// The whole point of deriving the wobble from the day index instead of
    /// `Double.random`: two generations of the same window are the same series.
    func testHistoryIsDeterministic() {
        let first = DemoData.generateHistory(endingOn: end, calendar: calendar)
        let second = DemoData.generateHistory(endingOn: end, calendar: calendar)

        XCTAssertEqual(first.count, second.count)
        for (left, right) in zip(first, second) {
            XCTAssertEqual(left.date, right.date)
            XCTAssertEqual(left.value ?? 0, right.value ?? 0, accuracy: 0.000_001)
            XCTAssertEqual(left.assetTotal ?? 0, right.assetTotal ?? 0, accuracy: 0.000_001)
            XCTAssertEqual(left.debtTotal ?? 0, right.debtTotal ?? 0, accuracy: 0.000_001)
        }
    }

    /// Time of day must not move a point onto a different calendar day.
    func testHistoryIgnoresTimeOfDay() {
        let morning = DemoData.generateHistory(endingOn: end.addingTimeInterval(8 * 3600), calendar: calendar)
        let evening = DemoData.generateHistory(endingOn: end.addingTimeInterval(22 * 3600), calendar: calendar)

        XCTAssertEqual(morning.map(\.date), evening.map(\.date))
    }

    // MARK: - Shape

    func testHistoryCoversAboutFourHundredDays() {
        let history = DemoData.generateHistory(endingOn: end, calendar: calendar)

        XCTAssertEqual(history.count, DemoData.dayCount)
        XCTAssertEqual(history.count, 400)
        XCTAssertEqual(history.last?.date, "2026-07-29")
        // 400 daily points ending today: the first is 399 days back.
        XCTAssertEqual(history.first?.date, "2025-06-25")
    }

    func testHistoryIsAscendingByDate() {
        let history = DemoData.generateHistory(endingOn: end, calendar: calendar)

        for (earlier, later) in zip(history, history.dropFirst()) {
            XCTAssertLessThan(earlier.date, later.date)
        }
    }

    func testHistoryValuesArePositiveAndFinite() {
        let history = DemoData.generateHistory(endingOn: end, calendar: calendar)

        for point in history {
            for figure in [point.value, point.assetTotal, point.debtTotal] {
                guard let value = figure else {
                    XCTFail("\(point.date) is missing a figure")
                    continue
                }
                XCTAssertTrue(value.isFinite, "\(point.date) is not finite")
                XCTAssertGreaterThan(value, 0, "\(point.date) is not positive")
            }
        }
    }

    /// Each point's own totals have to balance, or the demo's stat tiles would
    /// disagree with its chart.
    func testEveryHistoryPointBalances() {
        for point in DemoData.generateHistory(endingOn: end, calendar: calendar) {
            let assets = point.assetTotal ?? 0
            let debts = point.debtTotal ?? 0
            let netWorth = point.value ?? 0
            XCTAssertEqual(assets - debts, netWorth, accuracy: 0.01, "\(point.date) does not balance")
        }
    }

    /// The wobble is enveloped to zero at both ends, so the series lands exactly
    /// on the snapshot the hero number reads from.
    func testHistoryEndpointsMatchTheSnapshot() {
        let history = DemoData.generateHistory(endingOn: end, calendar: calendar)

        XCTAssertEqual(history.first?.value ?? 0, DemoData.startNetWorth, accuracy: 0.01)
        XCTAssertEqual(history.first?.debtTotal ?? 0, DemoData.startDebtTotal, accuracy: 0.01)
        XCTAssertEqual(history.last?.value ?? 0, DemoData.snapshot.netWorth, accuracy: 0.01)
        XCTAssertEqual(history.last?.assetTotal ?? 0, DemoData.snapshot.assetTotal, accuracy: 0.01)
        XCTAssertEqual(history.last?.debtTotal ?? 0, DemoData.snapshot.debtTotal, accuracy: 0.01)
    }

    /// Believable, not flat and not a rocket: the demo trends up overall while
    /// wobbling on the way, which is what makes the chart worth showing.
    func testHistoryTrendsUpwardWithWobble() {
        let values = DemoData.generateHistory(endingOn: end, calendar: calendar).compactMap(\.value)

        XCTAssertGreaterThan(values.last ?? 0, values.first ?? 0)
        // Not monotonic — a curve that only ever rises looks synthetic.
        let declines = zip(values, values.dropFirst()).filter { $1 < $0 }.count
        XCTAssertGreaterThan(declines, 20, "the series has no down days")
        // ...but the wobble stays inside a couple of percent day over day, so no
        // single step reads as a crash.
        for (earlier, later) in zip(values, values.dropFirst()) {
            XCTAssertLessThan(abs(later - earlier) / earlier, 0.02)
        }
    }

    // MARK: - Snapshot, trends, comps

    func testSnapshotIsInternallyConsistent() {
        let snapshot = DemoData.snapshot

        XCTAssertEqual(snapshot.assetTotal - snapshot.debtTotal, snapshot.netWorth, accuracy: 0.01)
        XCTAssertGreaterThan(snapshot.netWorth, 0)
        XCTAssertFalse(snapshot.topHoldings.isEmpty)
        // Holdings are a subset of the assets, never more than all of them.
        XCTAssertLessThanOrEqual(snapshot.topHoldings.reduce(0) { $0 + $1.value }, snapshot.assetTotal)
        XCTAssertTrue(snapshot.topHoldings.allSatisfy { $0.value > 0 && $0.sheet != nil })
        XCTAssertEqual(snapshot.allocation.values.reduce(0, +), 100, accuracy: 0.01)
    }

    func testSnapshotIsMarkedAsDemo() {
        XCTAssertTrue(DemoData.isDemo(DemoData.snapshot))
        XCTAssertFalse(DemoData.isDemo(.sample))
    }

    /// The welcome screen's widget previews read every one of these, so a nil
    /// would silently swap a preview for its empty state. All four stay positive
    /// whatever day the demo runs on: the series rises across every reference
    /// window, down to yesterday.
    func testTrendsArePopulatedAndPositive() {
        let trends = DemoData.trends

        for candidate in [trends.day, trends.year, trends.ytd, trends.qtd] {
            guard let change = candidate else {
                XCTFail("a demo trend is missing")
                continue
            }
            XCTAssertGreaterThan(change.amount, 0)
            XCTAssertGreaterThan(change.percent, 0)
        }
    }

    /// Percentages have to be derivable from the amounts, or the demo shows a
    /// figure that contradicts itself.
    func testTrendPercentagesAgreeWithAmounts() {
        for candidate in [DemoData.trends.day, DemoData.trends.ytd, DemoData.trends.year, DemoData.trends.qtd] {
            guard let change = candidate else { continue }
            let reference = DemoData.snapshot.netWorth - change.amount
            XCTAssertEqual(change.amount / reference * 100, change.percent, accuracy: 0.05)
        }
    }

    /// The reason the trends are computed from the history instead of typed in:
    /// the widget previews and the chart sit on one screen, so their YTD and 1Y
    /// figures must not disagree. They are not identical — `TrendsCalculator`
    /// references the last point *before* the period, the chart window starts on
    /// its first day — but they have to be within rounding of each other.
    func testTrendsAgreeWithTheChartWindows() {
        let now = Date()
        let points = DemoData.netWorthPoints

        for (label, change, range) in [
            ("YTD", DemoData.trends.ytd, ChartRange.ytd),
            ("1Y", DemoData.trends.year, ChartRange.year),
        ] {
            guard let change else {
                XCTFail("\(label) trend is missing")
                continue
            }
            let window = OverviewChart.filter(points, to: range, now: now, calendar: .current)
            guard let charted = OverviewChart.change(in: window) else {
                XCTFail("\(label) window has no delta")
                continue
            }
            XCTAssertEqual(
                change.percent,
                charted.percent,
                accuracy: 2,
                "\(label): widgets say \(change.percent)%, the chart says \(charted.percent)%"
            )
        }
    }

    func testCompsArePopulated() {
        let comps = DemoData.comps

        XCTAssertFalse(comps.isEmpty)
        XCTAssertNotNil(comps.sp500)
        XCTAssertNotNil(comps.dowJones)
        XCTAssertNotNil(comps.btc)
    }

    // MARK: - Parsed series

    func testParsedSeriesMatchTheHistory() {
        XCTAssertEqual(DemoData.netWorthPoints.count, DemoData.history.count)
        XCTAssertEqual(DemoData.assetPoints.count, DemoData.history.count)
        XCTAssertEqual(DemoData.debtPoints.count, DemoData.history.count)

        for (earlier, later) in zip(DemoData.netWorthPoints, DemoData.netWorthPoints.dropFirst()) {
            XCTAssertLessThan(earlier.date, later.date)
        }
        XCTAssertEqual(DemoData.netWorthPoints.last?.value ?? 0, DemoData.snapshot.netWorth, accuracy: 0.01)
    }

    /// Every window the range pills offer has to have something to draw: the
    /// welcome screen offers all six ranges with no empty state behind them, so
    /// each one needs at least two points and a delta of its own.
    func testEveryRangeHasEnoughPointsToChart() {
        let now = end.addingTimeInterval(15 * 3600)
        let points = OverviewChart.points(
            from: DemoData.generateHistory(endingOn: end, calendar: calendar),
            calendar: calendar
        )

        for range in ChartRange.allCases {
            let window = OverviewChart.filter(points, to: range, now: now, calendar: calendar)
            XCTAssertGreaterThanOrEqual(window.count, 2, "\(range.label) has nothing to draw")
            XCTAssertNotNil(OverviewChart.change(in: window), "\(range.label) has no delta")
        }
    }
}

// MARK: - Detail, profile and investable series

extension DemoDataTests {
    func testDetailAssetsSumToTheAssetTotal() throws {
        let detail = DemoData.detail
        let sum = detail.assets.reduce(0) { $0 + $1.value }
        XCTAssertEqual(sum, try XCTUnwrap(detail.assetTotal), accuracy: 0.01,
                       "the demo's asset rows must add up to the total it prints")
    }

    func testDetailNetWorthIsAssetsMinusDebts() throws {
        let detail = DemoData.detail
        let assets = try XCTUnwrap(detail.assetTotal)
        let debts = try XCTUnwrap(detail.debtTotal)
        XCTAssertEqual(try XCTUnwrap(detail.netWorth), assets - debts, accuracy: 0.01)
    }

    func testDetailAgreesWithTheSnapshot() throws {
        XCTAssertEqual(try XCTUnwrap(DemoData.detail.netWorth), DemoData.snapshot.netWorth, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(DemoData.detail.assetTotal), DemoData.snapshot.assetTotal, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(DemoData.detail.debtTotal), DemoData.snapshot.debtTotal, accuracy: 0.01)
        XCTAssertEqual(DemoData.detail.currency, DemoData.snapshot.currency)
    }

    func testDetailPopulatesTheModulesTheOverviewRenders() throws {
        let detail = DemoData.detail
        XCTAssertNotNil(detail.cashOnHand, "the cash on hand module would be empty")
        XCTAssertNotNil(detail.estimatedTax, "the tax estimate module would be empty")
        XCTAssertNotNil(detail.investableTotal, "the investable hero line would be empty")
        XCTAssertGreaterThan(detail.assets.count, 5, "the composition breakdown needs rows to group")
    }

    /// The demo has to advertise every screen the signed-in app has, and the
    /// Debts tab is one of them: without debt rows it would render its empty
    /// state in the demo and read as a feature that does not work.
    func testDebtRowsSumToTheDebtTotal() throws {
        let debts = try XCTUnwrap(DemoData.detail.debts)

        XCTAssertFalse(debts.isEmpty, "the Debts tab would be empty in the demo")
        XCTAssertEqual(
            debts.reduce(0) { $0 + $1.value },
            try XCTUnwrap(DemoData.detail.debtTotal),
            accuracy: 0.01,
            "the demo's debt rows must add up to the total it prints"
        )
        XCTAssertTrue(debts.allSatisfy { $0.value > 0 }, "debts are stated as positive magnitudes")
        XCTAssertTrue(debts.allSatisfy { $0.sheet != nil }, "every demo debt is filed")
    }

    func testAssetsCoverSeveralSheetsSoCompositionHasGroups() {
        let sheets = Set(DemoData.detail.assets.compactMap(\.sheet))
        XCTAssertGreaterThan(sheets.count, 3, "grouping by sheet should produce several bars")
        XCTAssertTrue(DemoData.detail.assets.contains { $0.section == nil },
                      "keep an unsectioned asset so that path is exercised")
    }

    func testHistoryCarriesInvestableForTheSecondChartSeries() throws {
        let withInvestable = DemoData.history.filter { $0.investibleTotal != nil }
        XCTAssertEqual(withInvestable.count, DemoData.history.count,
                       "every point needs an investable value or the second series breaks up")

        let last = try XCTUnwrap(DemoData.history.last?.investibleTotal)
        let net = try XCTUnwrap(DemoData.history.last?.value)
        XCTAssertLessThan(last, net, "investable is a slice of net worth, never more")
        XCTAssertGreaterThan(last, net * 0.5, "…but not a trivial one")
    }

    func testProfileGivesTheGreetingAName() throws {
        let name = try XCTUnwrap(DemoData.profile.name)
        XCTAssertNotNil(Greeting.firstName(from: name),
                        "the demo name must survive the generic-name filter")
    }
}

// MARK: - Coverage

/// The demo screen renders the same views the signed-in app does, so anything
/// `AppStore` exposes needs a `DemoData` counterpart — otherwise a module that
/// works with real data silently renders empty in the demo. That happened twice:
/// first `investibleTotal` was nil so the second chart series had nothing to
/// draw, then `detail` and `profile` did not exist at all, hiding cash on hand,
/// the tax estimate and the composition breakdown.
///
/// These tests are the guard. If you add an observable surface to `AppStore`,
/// add it to `DemoData` and assert it here.
extension DemoDataTests {
    func testDemoCoversEverySurfaceTheStoreExposes() {
        // AppStore's observable surface, as of this test:
        // snapshot, trends, comps, detail, profile, portfolios, settings.
        XCTAssertFalse(DemoData.snapshot.portfolioName.isEmpty, "snapshot")
        XCTAssertNotNil(DemoData.trends.ytd, "trends")
        XCTAssertNotNil(DemoData.comps.sp500, "comps")
        XCTAssertNotNil(DemoData.detail.cashOnHand, "detail")
        XCTAssertNotNil(DemoData.profile.name, "profile")
        XCTAssertFalse(DemoData.portfolios.isEmpty, "portfolios")
        XCTAssertTrue(DemoData.settings.compactNumbers, "settings")
    }

    func testEveryChartSeriesTheOverviewDrawsHasPoints() {
        // One series per line the hero chart and the stat cards can draw.
        XCTAssertGreaterThan(DemoData.netWorthPoints.count, 300, "net worth series")
        XCTAssertGreaterThan(DemoData.investablePoints.count, 300, "investable series")
        XCTAssertGreaterThan(DemoData.assetPoints.count, 300, "asset series")
        XCTAssertGreaterThan(DemoData.debtPoints.count, 300, "debt series")
    }

    func testInvestableSeriesTracksButNeverExceedsNetWorth() throws {
        let net = DemoData.netWorthPoints
        let inv = DemoData.investablePoints
        XCTAssertEqual(net.count, inv.count, "the two series must line up point for point")

        for (n, i) in zip(net, inv) {
            XCTAssertEqual(n.date, i.date)
            XCTAssertLessThan(i.value, n.value, "investable is a slice of net worth")
            XCTAssertGreaterThan(i.value, n.value * 0.5, "…and not a trivial one")
        }

        // The share must actually move, or drawing both lines says nothing and
        // the CAGR rows for net worth and investable read identically.
        let firstShare = try XCTUnwrap(inv.first).value / XCTUnwrap(net.first).value
        let lastShare = try XCTUnwrap(inv.last).value / XCTUnwrap(net.last).value
        XCTAssertGreaterThan(abs(lastShare - firstShare), 0.02,
                             "investable's share of net worth should drift over the series")
    }

    func testPortfoliosAreDistinctSoASwitcherIsMeaningful() {
        let ids = Set(DemoData.portfolios.map(\.id))
        XCTAssertEqual(ids.count, DemoData.portfolios.count, "duplicate portfolio ids")
        XCTAssertGreaterThan(DemoData.portfolios.count, 1, "a switcher needs somewhere to switch to")
    }
}
