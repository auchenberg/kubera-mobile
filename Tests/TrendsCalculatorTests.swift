import XCTest

final class TrendsCalculatorTests: XCTestCase {
    /// UTC so the "yyyy-MM-dd" points land on the day boundaries the
    /// assertions assume, whatever the test machine's zone is.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-07-28 12:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 7, day: 28, hour: 12
        ))!
    }

    private let currentNetWorth = 1_200_000.0

    private func point(_ date: String, _ value: Double?) -> KuberaAPI.HistoryPoint {
        KuberaAPI.HistoryPoint(
            date: date,
            value: value,
            assetTotal: nil,
            debtTotal: nil,
            investibleTotal: nil
        )
    }

    /// Synthetic series shaped like a real portfolio history: sparse early
    /// points, denser recent ones, chosen for round expected changes.
    private var sampleSeries: [KuberaAPI.HistoryPoint] {
        [
            point("2024-03-11", 500_000),
            point("2025-07-28", 800_000),
            point("2025-12-31", 1_000_000),
            point("2026-06-30", 1_150_000),
            point("2026-07-27", 1_190_000),
            // Today's own point must not be used as the 1-day reference.
            point("2026-07-28", 1_198_000),
        ]
    }

    func testComputesDayYearAndYtdFromSampleSeries() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: sampleSeries,
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))

        let day = try XCTUnwrap(trends.day)
        XCTAssertEqual(day.amount, 10_000, accuracy: 0.01)
        XCTAssertEqual(day.percent, 0.8403, accuracy: 0.0001)

        let year = try XCTUnwrap(trends.year)
        XCTAssertEqual(year.amount, 400_000, accuracy: 0.01)
        XCTAssertEqual(year.percent, 50.0, accuracy: 0.01)

        let ytd = try XCTUnwrap(trends.ytd)
        XCTAssertEqual(ytd.amount, 200_000, accuracy: 0.01)
        XCTAssertEqual(ytd.percent, 20.0, accuracy: 0.01)

        let qtd = try XCTUnwrap(trends.qtd)
        XCTAssertEqual(qtd.amount, 50_000, accuracy: 0.01)
        XCTAssertEqual(qtd.percent, 4.3478, accuracy: 0.001)

        XCTAssertEqual(trends.updatedAt, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testQtdMissingWhenSeriesStartsThisQuarter() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: [point("2026-07-10", 1_100_000), point("2026-07-27", 1_190_000)],
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))

        XCTAssertNil(trends.qtd)
        XCTAssertNotNil(trends.day)
    }

    func testUnsortedSeriesYieldsTheSameReferences() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: sampleSeries.reversed(),
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(try XCTUnwrap(trends.day).amount, 10_000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(trends.ytd).amount, 200_000, accuracy: 0.01)
    }

    func testSeriesYoungerThanAYearHasNoYearOrYtdChange() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: [point("2026-06-01", 1_100_000), point("2026-07-27", 1_190_000)],
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))

        XCTAssertNil(trends.year)
        XCTAssertNil(trends.ytd)
        XCTAssertNotNil(trends.day)
    }

    func testEmptySeriesReturnsNil() {
        XCTAssertNil(TrendsCalculator.compute(
            series: [],
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))
    }

    func testSeriesWithoutUsablePointsReturnsNil() {
        let garbage = [
            point("2026-07-27", nil),
            point("not-a-date", 1_000),
            point("", 2_000),
        ]

        XCTAssertNil(TrendsCalculator.compute(
            series: garbage,
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))
    }

    func testZeroReferenceGivesZeroPercent() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: [point("2026-07-27", 0)],
            currentNetWorth: currentNetWorth,
            now: now,
            calendar: calendar
        ))

        let day = try XCTUnwrap(trends.day)
        XCTAssertEqual(day.amount, currentNetWorth, accuracy: 0.01)
        XCTAssertEqual(day.percent, 0, accuracy: 0.0001)
    }

    func testLossesProduceNegativeChanges() throws {
        let trends = try XCTUnwrap(TrendsCalculator.compute(
            series: [point("2026-07-27", 1_000_000)],
            currentNetWorth: 900_000,
            now: now,
            calendar: calendar
        ))

        let day = try XCTUnwrap(trends.day)
        XCTAssertEqual(day.amount, -100_000, accuracy: 0.01)
        XCTAssertEqual(day.percent, -10, accuracy: 0.01)
    }
}
