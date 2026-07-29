import XCTest

/// All figures here are synthetic (a fictional ~$1.2M portfolio); this repo is
/// public. Dates run in UTC so the range arithmetic is deterministic wherever
/// the suite runs.
final class OverviewChartTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mid-afternoon on purpose: cutoffs must anchor to the start of the day, or
    /// every range loses its boundary point.
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
        _ value: Double?,
        assets: Double? = nil,
        debts: Double? = nil
    ) -> KuberaAPI.HistoryPoint {
        KuberaAPI.HistoryPoint(
            date: date,
            value: value,
            assetTotal: assets,
            debtTotal: debts,
            investibleTotal: nil
        )
    }

    // MARK: - Parsing

    func testParseDropsUnparseableDatesAndMissingValues() {
        let parsed = OverviewChart.points(
            from: [
                historyPoint("2026-07-01", 1_200_000),
                historyPoint("not a date", 1_210_000),
                historyPoint("", 1_220_000),
                historyPoint("07/02/2026", 1_230_000),
                historyPoint("2026-07-03", nil),
                historyPoint("2026-07-04", 1_240_000),
            ],
            calendar: calendar
        )

        XCTAssertEqual(parsed.map(\.value), [1_200_000, 1_240_000])
        XCTAssertEqual(parsed.map(\.date), [day("2026-07-01"), day("2026-07-04")])
    }

    func testParseSortsAscending() {
        let parsed = OverviewChart.points(
            from: [
                historyPoint("2026-07-04", 1_240_000),
                historyPoint("2026-07-01", 1_200_000),
                historyPoint("2026-07-03", 1_230_000),
            ],
            calendar: calendar
        )

        XCTAssertEqual(parsed.map(\.value), [1_200_000, 1_230_000, 1_240_000])
    }

    func testParseReadsAlternateFigures() {
        let series = [
            historyPoint("2026-07-01", 1_200_000, assets: 1_600_000, debts: 400_000),
            historyPoint("2026-07-02", 1_240_000, assets: 1_620_000, debts: nil),
        ]

        let assets = OverviewChart.points(from: series, calendar: calendar) { $0.assetTotal }
        let debts = OverviewChart.points(from: series, calendar: calendar) { $0.debtTotal }

        XCTAssertEqual(assets.map(\.value), [1_600_000, 1_620_000])
        XCTAssertEqual(debts.map(\.value), [400_000], "a point without a debt figure is dropped, not zeroed")
    }

    // MARK: - Range windowing

    func testWeekIncludesThePointExactlyOnTheCutoff() {
        let points = [
            point("2026-07-21", 1_190_000), // one day before the cutoff
            point("2026-07-22", 1_200_000), // exactly on it
            point("2026-07-29", 1_240_000),
        ]

        let filtered = OverviewChart.filter(points, to: .week, now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.value), [1_200_000, 1_240_000])
    }

    func testMonthQuarterAndYearCutoffs() {
        let points = [
            point("2025-07-28", 1_000_000), // outside 1Y by a day
            point("2025-07-29", 1_010_000), // on the 1Y cutoff
            point("2026-04-29", 1_100_000), // on the 3M cutoff
            point("2026-06-29", 1_200_000), // on the 1M cutoff
            point("2026-07-29", 1_240_000),
        ]

        XCTAssertEqual(
            OverviewChart.filter(points, to: .month, now: now, calendar: calendar).map(\.value),
            [1_200_000, 1_240_000]
        )
        XCTAssertEqual(
            OverviewChart.filter(points, to: .quarter, now: now, calendar: calendar).map(\.value),
            [1_100_000, 1_200_000, 1_240_000]
        )
        XCTAssertEqual(
            OverviewChart.filter(points, to: .year, now: now, calendar: calendar).map(\.value),
            [1_010_000, 1_100_000, 1_200_000, 1_240_000]
        )
    }

    func testYTDStartsAtJanuaryFirst() {
        let points = [
            point("2025-12-31", 1_100_000),
            point("2026-01-01", 1_110_000),
            point("2026-07-29", 1_240_000),
        ]

        let filtered = OverviewChart.filter(points, to: .ytd, now: now, calendar: calendar)

        XCTAssertEqual(filtered.map(\.value), [1_110_000, 1_240_000])
    }

    func testAllKeepsEverythingAndHasNoCutoff() {
        let points = [point("2019-01-01", 400_000), point("2026-07-29", 1_240_000)]

        XCTAssertNil(OverviewChart.cutoff(for: .all, now: now, calendar: calendar))
        XCTAssertEqual(OverviewChart.filter(points, to: .all, now: now, calendar: calendar).count, 2)
    }

    func testFilteringAnEmptySeriesStaysEmpty() {
        XCTAssertTrue(OverviewChart.filter([], to: .month, now: now, calendar: calendar).isEmpty)
    }

    // MARK: - Y domain

    func testYDomainPadsTheVisibleSpan() {
        let domain = OverviewChart.yDomain([
            point("2026-07-01", 1_200_000),
            point("2026-07-02", 1_300_000),
        ])

        let pad = 100_000 * OverviewChart.yPadding
        XCTAssertEqual(domain.lowerBound, 1_200_000 - pad, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 1_300_000 + pad, accuracy: 0.001)
        XCTAssertGreaterThan(domain.lowerBound, 0, "the domain is never zero-based")
    }

    func testYDomainOfEmptySeries() {
        XCTAssertEqual(OverviewChart.yDomain([]), 0 ... 1)
    }

    func testYDomainPadsAroundAFlatSeries() {
        let domain = OverviewChart.yDomain([
            point("2026-07-01", 1_200_000),
            point("2026-07-02", 1_200_000),
        ])

        XCTAssertLessThan(domain.lowerBound, 1_200_000, "a flat line must not sit on the plot edge")
        XCTAssertGreaterThan(domain.upperBound, 1_200_000)
        XCTAssertEqual(domain.lowerBound, 1_200_000 - 1_200_000 * OverviewChart.yPadding, accuracy: 0.001)
    }

    func testYDomainOfAnAllZeroSeriesStillHasWidth() {
        let domain = OverviewChart.yDomain([point("2026-07-01", 0), point("2026-07-02", 0)])

        XCTAssertLessThan(domain.lowerBound, domain.upperBound)
    }

    func testYDomainOfASinglePoint() {
        let domain = OverviewChart.yDomain([point("2026-07-01", 1_200_000)])

        XCTAssertLessThan(domain.lowerBound, 1_200_000)
        XCTAssertGreaterThan(domain.upperBound, 1_200_000)
    }

    // MARK: - Nearest point

    func testNearestPicksTheClosestPoint() {
        let points = [
            point("2026-07-01", 1_200_000),
            point("2026-07-10", 1_220_000),
            point("2026-07-20", 1_240_000),
        ]

        let target = day("2026-07-08")
        XCTAssertEqual(OverviewChart.nearest(to: target, in: points)?.value, 1_220_000)
    }

    func testNearestBreaksTiesTowardTheEarlierPoint() {
        let points = [point("2026-07-01", 1_200_000), point("2026-07-03", 1_240_000)]

        XCTAssertEqual(OverviewChart.nearest(to: day("2026-07-02"), in: points)?.value, 1_200_000)
    }

    func testNearestClampsToTheSeriesEdges() {
        let points = [point("2026-07-01", 1_200_000), point("2026-07-20", 1_240_000)]

        XCTAssertEqual(OverviewChart.nearest(to: day("2020-01-01"), in: points)?.value, 1_200_000)
        XCTAssertEqual(OverviewChart.nearest(to: day("2030-01-01"), in: points)?.value, 1_240_000)
    }

    func testNearestOfEmptySeriesIsNil() {
        XCTAssertNil(OverviewChart.nearest(to: now, in: []))
    }

    // MARK: - Change

    func testChangeUsesFirstAndLastOfTheWindow() {
        let change = OverviewChart.change(in: [
            point("2026-07-01", 1_200_000),
            point("2026-07-10", 1_100_000), // a dip in between must not matter
            point("2026-07-20", 1_260_000),
        ])

        XCTAssertEqual(change?.amount, 60_000)
        XCTAssertEqual(change?.percent ?? 0, 5, accuracy: 0.0001)
    }

    func testChangeCanBeNegative() {
        let change = OverviewChart.change(in: [
            point("2026-07-01", 1_200_000),
            point("2026-07-20", 1_140_000),
        ])

        XCTAssertEqual(change?.amount, -60_000)
        XCTAssertEqual(change?.percent ?? 0, -5, accuracy: 0.0001)
    }

    func testChangeNeedsTwoPoints() {
        XCTAssertNil(OverviewChart.change(in: []))
        XCTAssertNil(OverviewChart.change(in: [point("2026-07-01", 1_200_000)]))
    }

    func testChangeFromAZeroReferenceIsNil() {
        XCTAssertNil(
            OverviewChart.change(in: [point("2026-07-01", 0), point("2026-07-20", 1_200_000)]),
            "a percentage against zero is meaningless, so the delta is hidden instead"
        )
    }

    // MARK: - Favorable direction

    func testRisingAssetsAreFavorableAndRisingDebtIsNot() {
        XCTAssertTrue(OverviewChart.isFavorable(19_100, metric: .asset))
        XCTAssertFalse(OverviewChart.isFavorable(-19_100, metric: .asset))
        XCTAssertTrue(OverviewChart.isFavorable(-1_180, metric: .debt), "paying down debt is good news")
        XCTAssertFalse(OverviewChart.isFavorable(1_180, metric: .debt))
    }

    func testNoChangeIsNotFavorable() {
        XCTAssertFalse(OverviewChart.isFavorable(0, metric: .asset))
        XCTAssertFalse(OverviewChart.isFavorable(0, metric: .debt))
    }

    // MARK: - Segments

    func testSegmentsBreakOnAGapAndKeepDenseRunsWhole() {
        let points = [
            point("2026-05-01", 1_200_000),
            point("2026-05-02", 1_205_000),
            point("2026-06-15", 1_230_000), // 44 days later
            point("2026-06-16", 1_240_000),
        ]

        let segments = OverviewChart.segments(points)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].map(\.value), [1_200_000, 1_205_000])
        XCTAssertEqual(segments[1].map(\.value), [1_230_000, 1_240_000])
    }

    func testSegmentsOfAContinuousSeriesIsOneRun() {
        let points = (1 ... 5).map { point(String(format: "2026-07-%02d", $0), 1_200_000 + Double($0) * 1_000) }

        XCTAssertEqual(OverviewChart.segments(points).count, 1)
    }

    func testSegmentsOfAnEmptySeriesIsEmpty() {
        XCTAssertTrue(OverviewChart.segments([]).isEmpty)
    }

    // MARK: - Allocation

    func testAllocationFoldsSmallSlicesIntoOther() {
        let segments = OverviewChart.allocationSegments([
            "Public equity": 42.1,
            "Real estate": 24.8,
            "Cash": 18.3,
            "Crypto": 9.4,
            "Collectibles": 2.9,
            "Loans": 2.5,
        ])

        XCTAssertEqual(segments.map(\.name), ["Public equity", "Real estate", "Cash", "Crypto", "Other"])
        XCTAssertEqual(segments.last?.percent ?? 0, 5.4, accuracy: 0.0001)
    }

    func testAllocationMergesIntoAnExistingOtherClass() {
        let segments = OverviewChart.allocationSegments([
            "Investable": 64,
            "Other": 30,
            "Crypto": 2,
        ])

        XCTAssertEqual(segments.map(\.name), ["Investable", "Other"])
        XCTAssertEqual(segments.last?.percent ?? 0, 32, accuracy: 0.0001)
    }

    func testAllocationDropsEmptyClassesAndRanksDescending() {
        let segments = OverviewChart.allocationSegments([
            "Real estate": 28,
            "Investable": 64,
            "Retired": 0,
        ])

        XCTAssertEqual(segments.map(\.name), ["Investable", "Real estate"])
    }
}
