import XCTest

/// All figures here are synthetic (a fictional ~$1.2M portfolio); this repo is
/// public. Dates run in UTC so the range arithmetic is deterministic wherever
/// the suite runs.
final class OverviewModulesTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mid-afternoon on purpose: the 1-day reference anchors to the start of the
    /// day, so a point recorded this morning must not count as yesterday.
    private lazy var now = day("2026-07-29").addingTimeInterval(15 * 3600)

    private func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    private func point(_ date: String, _ value: Double) -> ChartPoint {
        ChartPoint(date: day(date), value: value)
    }

    private func historyPoint(
        _ date: String,
        value: Double? = nil,
        assets: Double? = nil,
        debts: Double? = nil,
        investible: Double? = nil
    ) -> KuberaAPI.HistoryPoint {
        KuberaAPI.HistoryPoint(
            date: date,
            value: value,
            assetTotal: assets,
            debtTotal: debts,
            investibleTotal: investible
        )
    }

    private func asset(
        _ name: String,
        _ value: Double,
        sheet: String? = nil,
        section: String? = nil
    ) -> PortfolioDetail.Asset {
        PortfolioDetail.Asset(
            name: name,
            value: value,
            assetClass: nil,
            ticker: nil,
            sheet: sheet,
            section: section
        )
    }

    private func detail(
        cashOnHand: Double? = nil,
        estimatedTax: Double? = nil,
        investableTotal: Double? = nil,
        assets: [PortfolioDetail.Asset] = []
    ) -> PortfolioDetail {
        PortfolioDetail(
            currency: "USD",
            netWorth: 1_240_000,
            assetTotal: 1_318_400,
            debtTotal: 77_540,
            cashOnHand: cashOnHand,
            estimatedTax: estimatedTax,
            investableTotal: investableTotal,
            costBasis: nil,
            unrealizedGain: nil,
            assets: assets,
            // This suite is about the Overview's asset-side modules; the debt
            // rows are another screen's input.
            debts: nil,
            updatedAt: 0
        )
    }

    /// The sample book: $1.2M across five sheets, two rows on one of them, and a
    /// tail small enough to fold away.
    private var sampleAssets: [PortfolioDetail.Asset] {
        [
            asset("VTI", 300_000, sheet: "Brokerage", section: "Investable"),
            asset("VXUS", 200_000, sheet: "Brokerage", section: "Investable"),
            asset("Primary residence", 400_000, sheet: "Real estate", section: "Illiquid"),
            asset("401(k)", 250_000, sheet: "Retirement", section: "Investable"),
            asset("BTC", 40_000, sheet: "Crypto", section: "Investable"),
            asset("Watches", 10_000, sheet: "Collectibles", section: "Illiquid"),
        ]
    }

    private func investablePoints(_ series: [KuberaAPI.HistoryPoint]) -> [ChartPoint] {
        OverviewModules.investableSeries(from: series, calendar: calendar)
    }

    // MARK: - Per-metric trend

    func testTrendMeasuresDayAgainstLatestPointBeforeToday() throws {
        let series = [
            point("2026-07-27", 1_300_000),
            point("2026-07-28", 1_320_000),
            // Today's own point must not be the reference for the day change.
            point("2026-07-29", 1_330_000),
        ]

        let trend = OverviewModules.trend(in: series, current: 1_336_400, now: now, calendar: calendar)

        XCTAssertEqual(trend.day?.amount, 16_400)
        XCTAssertEqual(try XCTUnwrap(trend.day?.percent), 16_400 / 1_320_000 * 100, accuracy: 0.0001)
    }

    func testTrendMeasuresYearAgainstPointOnTheAnniversary() throws {
        let series = [
            point("2025-07-28", 1_100_000),
            point("2025-07-29", 1_120_000),
            point("2025-07-30", 1_140_000),
            point("2026-07-28", 1_320_000),
        ]

        let trend = OverviewModules.trend(in: series, current: 1_240_000, now: now, calendar: calendar)

        // On or before the anniversary, so a point dated exactly a year back is
        // the reference rather than the day before it.
        XCTAssertEqual(trend.year?.amount, 120_000)
        XCTAssertEqual(try XCTUnwrap(trend.year?.percent), 120_000 / 1_120_000 * 100, accuracy: 0.0001)
    }

    /// The case the naive implementation gets wrong: a log that only goes back
    /// three months has no 1-year change, and reporting 0% would claim the
    /// portfolio stood still for nine months it never recorded.
    func testTrendYearIsNilWhenSeriesDoesNotReachBackAYear() {
        let series = [
            point("2026-05-01", 1_180_000),
            point("2026-06-01", 1_200_000),
            point("2026-07-28", 1_220_000),
        ]

        let trend = OverviewModules.trend(in: series, current: 1_240_000, now: now, calendar: calendar)

        XCTAssertNil(trend.year)
        XCTAssertNotNil(trend.day, "a three-month log still has a day-over-day change")
    }

    func testTrendIsUnknownForAnEmptySeries() {
        let trend = OverviewModules.trend(in: [], current: 1_240_000, now: now, calendar: calendar)

        XCTAssertNil(trend.day)
        XCTAssertNil(trend.year)
    }

    func testTrendIsUnknownWhenTheCurrentValueIsMissing() {
        let series = [point("2026-07-28", 1_320_000)]

        let trend = OverviewModules.trend(in: series, current: nil, now: now, calendar: calendar)

        XCTAssertNil(trend.day)
        XCTAssertNil(trend.year)
    }

    /// Debts specifically: a portfolio that carried no debt a year ago has a
    /// real amount but no meaningful percentage, so the amount survives and the
    /// percent goes nil instead of dividing by zero.
    func testChangeFromAZeroReferenceKeepsTheAmountAndDropsThePercent() {
        let change = OverviewModules.change(from: 0, to: 77_540)

        XCTAssertEqual(change?.amount, 77_540)
        XCTAssertNil(change?.percent)
    }

    func testDebtTrendReadsNegativeWhenDebtShrinks() throws {
        let series = [
            point("2025-07-29", 96_000),
            point("2026-07-28", 78_720),
        ]

        let trend = OverviewModules.trend(in: series, current: 77_540, now: now, calendar: calendar)

        XCTAssertEqual(try XCTUnwrap(trend.day?.amount), -1_180, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trend.year?.amount), -18_460, accuracy: 0.0001)
        // Direction is the view's job via OverviewChart.isFavorable; the sign
        // here is only the arithmetic.
        XCTAssertTrue(OverviewChart.isFavorable(try XCTUnwrap(trend.year?.amount), metric: .debt))
    }

    // MARK: - YTD

    func testYTDMeasuresAgainstTheLastCloseOfLastYear() throws {
        let series = [
            point("2025-12-30", 1_100_000),
            point("2025-12-31", 1_120_000),
            point("2026-01-02", 1_130_000),
            point("2026-07-28", 1_230_000),
        ]

        let percent = OverviewModules.ytdPercent(in: series, current: 1_240_000, now: now, calendar: calendar)

        XCTAssertEqual(try XCTUnwrap(percent), 120_000 / 1_120_000 * 100, accuracy: 0.0001)
    }

    func testYTDIsNilWhenTheSeriesStartsThisYear() {
        let series = [
            point("2026-02-01", 1_180_000),
            point("2026-07-28", 1_230_000),
        ]

        XCTAssertNil(OverviewModules.ytdPercent(in: series, current: 1_240_000, now: now, calendar: calendar))
    }

    func testYTDIsNilWithoutACurrentValue() {
        let series = [point("2025-12-31", 1_120_000)]

        XCTAssertNil(OverviewModules.ytdPercent(in: series, current: nil, now: now, calendar: calendar))
    }

    // MARK: - CAGR

    func testCAGRCompoundsRatherThanAveraging() throws {
        // A doubling over (a day short of) four years is 2^(1/4) − 1 ≈ 18.9% a
        // year, not 100% ÷ 4 = 25%.
        let series = [point("2022-07-29", 1_200_000), point("2026-07-28", 2_400_000)]

        let cagr = OverviewModules.cagrPercent(in: series)

        XCTAssertEqual(try XCTUnwrap(cagr), 18.935, accuracy: 0.01)
    }

    func testCAGRIsNilForAShortSeries() {
        // Three months at +4% annualizes to a rate no portfolio holds; refusing
        // to state it is the point.
        let series = [point("2026-04-29", 1_200_000), point("2026-07-28", 1_248_000)]

        XCTAssertNil(OverviewModules.cagrPercent(in: series))
    }

    func testCAGRHonorsACustomMinimumSpan() {
        // Just under six months of history: nil at the default one-year floor,
        // available once the caller lowers the floor below the span.
        let series = [point("2026-01-29", 1_200_000), point("2026-07-28", 1_320_000)]

        XCTAssertNil(OverviewModules.cagrPercent(in: series))
        XCTAssertNotNil(OverviewModules.cagrPercent(in: series, minimumYears: 0.4))
    }

    func testCAGRIsNilWhenAnEndpointIsNotPositive() {
        XCTAssertNil(OverviewModules.cagrPercent(in: [point("2022-07-29", 0), point("2026-07-28", 1_240_000)]))
        XCTAssertNil(OverviewModules.cagrPercent(in: [point("2022-07-29", 1_240_000), point("2026-07-28", 0)]))
        XCTAssertNil(OverviewModules.cagrPercent(in: []))
    }

    // MARK: - Investable

    func testInvestableSeriesEndsOnTheNewestPointCarryingOne() {
        // Out of order, and the two newest points omit investable — the answer
        // is the latest point that has one, not the last element of the array.
        let series = [
            historyPoint("2026-07-20", value: 1_200_000, investible: 940_000),
            historyPoint("2026-07-28", value: 1_235_000),
            historyPoint("2026-07-24", value: 1_220_000, investible: 964_200),
            historyPoint("2026-07-29", value: 1_240_000),
        ]

        XCTAssertEqual(investablePoints(series).last?.value, 964_200)
    }

    func testInvestableSeriesIsEmptyWhenNoPointCarriesOne() {
        let series = [
            historyPoint("2026-07-28", value: 1_235_000),
            historyPoint("2026-07-29", value: 1_240_000),
        ]

        XCTAssertTrue(investablePoints(series).isEmpty)
        XCTAssertTrue(investablePoints([]).isEmpty)
    }

    /// Only a server-fetched series carries investable; the days the app logs
    /// itself write nil and win date collisions, so the newest investable point
    /// can be months behind the newest net worth point. A figure that old must
    /// not be printed as a current one.
    func testCurrentInvestableRejectsAStalePoint() {
        let stale = [
            historyPoint("2026-03-01", value: 1_180_000, investible: 900_000),
            historyPoint("2026-07-29", value: 1_240_000),
        ]

        XCTAssertNil(OverviewModules.currentInvestable(in: investablePoints(stale), now: now, calendar: calendar))
        // Still available as history — the chart draws it at its own dates.
        XCTAssertEqual(investablePoints(stale).last?.value, 900_000)
    }

    func testCurrentInvestableAcceptsAPointInsideTheWindow() {
        let fresh = [
            historyPoint("2026-07-24", value: 1_220_000, investible: 964_200),
            historyPoint("2026-07-29", value: 1_240_000),
        ]

        XCTAssertEqual(
            OverviewModules.currentInvestable(in: investablePoints(fresh), now: now, calendar: calendar),
            964_200
        )
    }

    func testCurrentInvestableHonorsACustomFreshnessWindow() {
        // Five days old: inside the default week, outside a two-day window.
        let series = [historyPoint("2026-07-24", value: 1_220_000, investible: 964_200)]

        XCTAssertEqual(
            OverviewModules.currentInvestable(in: investablePoints(series), now: now, calendar: calendar),
            964_200
        )
        XCTAssertNil(OverviewModules.currentInvestable(
            in: investablePoints(series),
            now: now,
            calendar: calendar,
            freshness: 2 * 24 * 60 * 60
        ))
    }

    /// The boundary the start-of-day anchor exists for: a point dated exactly a
    /// week back is inside the window even though `now` is mid-afternoon.
    func testCurrentInvestableCountsTheBoundaryDay() {
        XCTAssertEqual(
            OverviewModules.currentInvestable(
                in: investablePoints([historyPoint("2026-07-22", value: 1_220_000, investible: 964_200)]),
                now: now,
                calendar: calendar
            ),
            964_200
        )
        XCTAssertNil(OverviewModules.currentInvestable(
            in: investablePoints([historyPoint("2026-07-21", value: 1_220_000, investible: 964_200)]),
            now: now,
            calendar: calendar
        ))
    }

    func testCurrentInvestableIsNilWhenNoPointCarriesOne() {
        XCTAssertNil(OverviewModules.currentInvestable(in: [], now: now, calendar: calendar))
        XCTAssertNil(OverviewModules.currentInvestable(
            in: investablePoints([historyPoint("2026-07-29", value: 1_240_000)]),
            now: now,
            calendar: calendar
        ))
    }

    func testInvestableSeriesIsSortedAndDropsPointsWithoutTheField() {
        let series = [
            historyPoint("2026-07-24", value: 1_220_000, investible: 964_200),
            historyPoint("2026-07-28", value: 1_235_000),
            historyPoint("2026-07-20", value: 1_200_000, investible: 940_000),
        ]

        let points = OverviewModules.investableSeries(from: series, calendar: calendar)

        XCTAssertEqual(points.map(\.value), [940_000, 964_200])
        XCTAssertEqual(points.map(\.date), [day("2026-07-20"), day("2026-07-24")])
    }

    func testInvestableYTDUsesItsOwnSeriesAsBothReferenceAndCurrent() throws {
        let series = [
            historyPoint("2025-12-31", value: 1_120_000, investible: 840_000),
            historyPoint("2026-07-28", value: 1_235_000, investible: 964_200),
        ]
        let points = OverviewModules.investableSeries(from: series, calendar: calendar)

        let percent = OverviewModules.ytdPercent(
            in: points,
            current: points.last?.value,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(percent), 124_200 / 840_000 * 100, accuracy: 0.0001)
    }

    // MARK: - Investable source

    func testInvestablePrefersTheDetailFetch() {
        let history = [historyPoint("2026-07-28", value: 1_235_000, investible: 900_000)]

        XCTAssertEqual(
            OverviewModules.investable(
                detail: detail(investableTotal: 964_200),
                series: investablePoints(history),
                now: now,
                calendar: calendar
            ),
            964_200
        )
    }

    func testInvestableFallsBackToHistoryWhenTheDetailLacksIt() {
        let history = [historyPoint("2026-07-28", value: 1_235_000, investible: 900_000)]

        XCTAssertEqual(
            OverviewModules.investable(detail: detail(), series: investablePoints(history), now: now, calendar: calendar),
            900_000
        )
        XCTAssertEqual(
            OverviewModules.investable(detail: nil, series: investablePoints(history), now: now, calendar: calendar),
            900_000
        )
    }

    /// The fallback keeps the freshness guard, so a months-old history point
    /// still does not stand in for a live figure.
    func testInvestableFallbackStillRejectsStaleHistory() {
        let stale = [historyPoint("2026-03-01", value: 1_180_000, investible: 900_000)]

        XCTAssertNil(OverviewModules.investable(
            detail: detail(),
            series: investablePoints(stale),
            now: now,
            calendar: calendar
        ))
        XCTAssertNil(OverviewModules.investable(detail: nil, series: [], now: now, calendar: calendar))
    }

    // MARK: - Composition

    func testCompositionGroupsBySheetLargestFirst() {
        let groups = OverviewModules.composition(sampleAssets, by: .sheet)

        // Brokerage's two rows sum into one group, and Collectibles is under 3%
        // so it folds into a trailing Other.
        XCTAssertEqual(groups.map(\.name), ["Brokerage", "Real estate", "Retirement", "Crypto", "Other"])
        XCTAssertEqual(groups.map(\.value), [500_000, 400_000, 250_000, 40_000, 10_000])
    }

    func testCompositionPercentsAreSharesOfTheGroupedTotal() throws {
        let groups = OverviewModules.composition(sampleAssets, by: .sheet)

        let brokerage = try XCTUnwrap(groups.first { $0.name == "Brokerage" })
        XCTAssertEqual(brokerage.percent, 500_000 / 1_200_000 * 100, accuracy: 0.0001)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
    }

    func testCompositionGroupsBySection() {
        let groups = OverviewModules.composition(sampleAssets, by: .section)

        XCTAssertEqual(groups.map(\.name), ["Investable", "Illiquid"])
        XCTAssertEqual(groups.map(\.value), [790_000, 410_000])
    }

    /// Unfiled money is still money, so it gets a named row instead of being
    /// dropped out of the total.
    func testCompositionFilesAssetsWithoutALabelUnderUnsorted() {
        let assets = [
            asset("VTI", 900_000, sheet: "Brokerage"),
            asset("Loose ends", 200_000, sheet: nil),
            asset("Whitespace sheet", 100_000, sheet: "   "),
        ]

        let groups = OverviewModules.composition(assets, by: .sheet)

        XCTAssertEqual(groups.map(\.name), ["Brokerage", "Unsorted"])
        XCTAssertEqual(groups.map(\.value), [900_000, 300_000])
    }

    func testCompositionCapsTheRowCountAndFoldsTheTail() {
        let groups = OverviewModules.composition(sampleAssets, by: .sheet, maximumGroups: 2)

        XCTAssertEqual(groups.map(\.name), ["Brokerage", "Real estate", "Other"])
        XCTAssertEqual(groups.map(\.value), [500_000, 400_000, 300_000])
    }

    /// A sheet actually named "Other" absorbs the folded remainder rather than
    /// the list showing two rows with the same name.
    func testCompositionMergesIntoAnExistingOtherSheet() throws {
        let assets = [
            asset("VTI", 900_000, sheet: "Brokerage"),
            asset("Odds and ends", 60_000, sheet: "Other"),
            asset("Watches", 10_000, sheet: "Collectibles"),
        ]

        let groups = OverviewModules.composition(assets, by: .sheet)

        XCTAssertEqual(groups.map(\.name), ["Brokerage", "Other"])
        let other = try XCTUnwrap(groups.first { $0.name == "Other" })
        XCTAssertEqual(other.value, 70_000)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
    }

    /// A sheet that nets to zero or less has no share of a positive whole, so it
    /// leaves the composition rather than being drawn as a slice of it.
    func testCompositionDropsNonPositiveGroups() {
        let assets = [
            asset("VTI", 900_000, sheet: "Brokerage"),
            asset("Mortgage", -300_000, sheet: "Debts"),
            asset("Closed account", 0, sheet: "Dormant"),
        ]

        let groups = OverviewModules.composition(assets, by: .sheet)

        XCTAssertEqual(groups.map(\.name), ["Brokerage"])
        XCTAssertEqual(groups.map(\.percent), [100])
    }

    func testIsLabelledRejectsASingleUnsortedGroup() {
        let unlabelled = OverviewModules.composition([asset("VTI", 900_000, sheet: nil)], by: .sheet)
        XCTAssertEqual(unlabelled.map(\.name), [OverviewModules.unsortedGroupName])
        XCTAssertFalse(OverviewModules.isLabelled(unlabelled))

        XCTAssertFalse(OverviewModules.isLabelled([]))
        XCTAssertTrue(OverviewModules.isLabelled(OverviewModules.composition(sampleAssets, by: .sheet)))
        XCTAssertTrue(OverviewModules.isLabelled(
            OverviewModules.composition([asset("VTI", 900_000, sheet: "Brokerage")], by: .sheet)
        ))
    }

    func testCompositionIsEmptyWithoutPositiveAssets() {
        XCTAssertTrue(OverviewModules.composition([], by: .sheet).isEmpty)
        XCTAssertTrue(OverviewModules.composition([asset("Mortgage", -300_000, sheet: "Debts")], by: .sheet).isEmpty)
    }

    // MARK: - Comps

    func testCompsKeepKuberaOrderAndDropMissingBenchmarks() {
        let comps = OverviewModules.comps(MarketComps(
            sp500: 8.2,
            dowJones: nil,
            btc: 21.4,
            updatedAt: 0
        ))

        XCTAssertEqual(comps.map(\.name), ["S&P 500", "BTC"])
        XCTAssertEqual(comps.map(\.percent), [8.2, 21.4])
    }

    func testCompsAreEmptyWithoutAFetch() {
        XCTAssertTrue(OverviewModules.comps(nil).isEmpty)
        XCTAssertTrue(OverviewModules.comps(MarketComps(sp500: nil, dowJones: nil, btc: nil, updatedAt: 0)).isEmpty)
    }

    // MARK: - Shared Y domain

    func testYDomainSpansEverySeriesInThePlot() {
        let netWorth = [point("2026-07-01", 1_200_000), point("2026-07-28", 1_240_000)]
        let investable = [point("2026-07-01", 900_000), point("2026-07-28", 964_000)]

        let domain = OverviewModules.yDomain([netWorth, investable])

        // Investable sets the floor and net worth the ceiling, both padded, so
        // the two curves keep their real vertical gap.
        XCTAssertLessThan(domain.lowerBound, 900_000)
        XCTAssertGreaterThan(domain.upperBound, 1_240_000)
        XCTAssertEqual(domain, OverviewChart.yDomain(netWorth + investable))
    }

    func testYDomainToleratesEmptyAndSingleSeries() {
        XCTAssertEqual(OverviewModules.yDomain([]), 0 ... 1)
        XCTAssertEqual(OverviewModules.yDomain([[], []]), 0 ... 1)
        XCTAssertEqual(
            OverviewModules.yDomain([[point("2026-07-28", 1_240_000)], []]),
            OverviewChart.yDomain([point("2026-07-28", 1_240_000)])
        )
    }
}

// MARK: - Kubera's aggregate row

/// When Kubera answers with a ranked, cut-off holdings table, the last row is an
/// aggregate like "Others (12 positions)". It arrives with no sheet and no
/// section, so it used to be grouped as unfiled money — a bar claiming that much
/// of the portfolio had never been filed. It belongs in the folded tail instead.
extension OverviewModulesTests {
    /// The measured shape from the audit: one real holding plus the aggregate.
    private var rankedTableRows: [PortfolioDetail.Asset] {
        [
            asset("Index funds", 620_000, sheet: "Investments", section: "Taxable"),
            asset("Others (12 positions)", 44_000),
        ]
    }

    func testTheAggregateJoinsTheFoldedTailRatherThanUnsorted() {
        for level in OverviewModules.CompositionLevel.allCases {
            let groups = OverviewModules.composition(rankedTableRows, by: level)

            XCTAssertFalse(
                groups.contains { $0.name == OverviewModules.unsortedGroupName },
                "\(level): an aggregate is not unfiled money"
            )
            XCTAssertEqual(
                groups.first { $0.name == OverviewModules.otherGroupName }?.value,
                44_000,
                "\(level): the aggregate's value belongs to the tail"
            )
        }
    }

    /// Conservation: the bars are read against the asset total, so nothing may
    /// be lost on the way into the tail.
    func testTheAggregatesValueSurvivesGrouping() {
        for level in OverviewModules.CompositionLevel.allCases {
            let total = OverviewModules.composition(rankedTableRows, by: level)
                .reduce(0) { $0 + $1.value }
            XCTAssertEqual(total, 664_000, accuracy: 0.01, "\(level)")
        }
    }

    /// A real "Other" sheet and the aggregate are the same money either way, so
    /// they sum into one row rather than producing two with one name.
    func testTheAggregateMergesWithAnExistingOtherGroup() {
        let groups = OverviewModules.composition(
            rankedTableRows + [asset("Odds and ends", 6_000, sheet: OverviewModules.otherGroupName)],
            by: .sheet
        )

        XCTAssertEqual(groups.filter { $0.name == OverviewModules.otherGroupName }.count, 1)
        XCTAssertEqual(groups.first { $0.name == OverviewModules.otherGroupName }?.value, 50_000)
    }
}
