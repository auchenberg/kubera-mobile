import XCTest

final class MarketCompsTests: XCTestCase {
    /// UTC so the Jan 1 boundary the assertions assume does not move with the
    /// test machine's zone.
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

    /// Yahoo stamps each daily bar at the session open, in unix seconds.
    private func stamp(_ year: Int, _ month: Int, _ day: Int) -> Int {
        Int(calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: year, month: month, day: day, hour: 14, minute: 30
        ))!.timeIntervalSince1970)
    }

    private func ytd(_ timestamps: [Int], _ closes: [Double?]) -> Double? {
        MarketCompsCalculator.ytdPercent(
            timestamps: timestamps,
            closes: closes,
            now: now,
            calendar: calendar
        )
    }

    func testReferenceIsTheLastCloseBeforeJanuaryFirst() throws {
        let percent = try XCTUnwrap(ytd(
            [stamp(2025, 12, 30), stamp(2025, 12, 31), stamp(2026, 1, 15), stamp(2026, 7, 27)],
            [4_800, 5_000, 5_200, 5_400]
        ))

        // Dec 31 is the reference, not Dec 30: 5400 / 5000 − 1.
        XCTAssertEqual(percent, 8, accuracy: 0.0001)
    }

    func testNullClosesAreSkippedForBothEnds() throws {
        let percent = try XCTUnwrap(ytd(
            [stamp(2025, 12, 30), stamp(2025, 12, 31), stamp(2026, 7, 27), stamp(2026, 7, 28)],
            [5_000, nil, 5_500, nil]
        ))

        // Falls back to Dec 30 and Jul 27: 5500 / 5000 − 1.
        XCTAssertEqual(percent, 10, accuracy: 0.0001)
    }

    func testLossesComeBackNegative() throws {
        let percent = try XCTUnwrap(ytd(
            [stamp(2025, 12, 31), stamp(2026, 7, 27)],
            [100_000, 73_000]
        ))

        XCTAssertEqual(percent, -27, accuracy: 0.0001)
    }

    func testUnsortedSeriesYieldsTheSamePercent() throws {
        let percent = try XCTUnwrap(ytd(
            [stamp(2026, 7, 27), stamp(2025, 12, 31), stamp(2026, 1, 15)],
            [5_400, 5_000, 5_200]
        ))

        XCTAssertEqual(percent, 8, accuracy: 0.0001)
    }

    func testSeriesEntirelyInsideThisYearHasNoReference() {
        XCTAssertNil(ytd(
            [stamp(2026, 1, 2), stamp(2026, 7, 27)],
            [5_000, 5_400]
        ))
    }

    func testZeroReferenceReturnsNil() {
        XCTAssertNil(ytd(
            [stamp(2025, 12, 31), stamp(2026, 7, 27)],
            [0, 5_400]
        ))
    }

    func testAllClosesNullReturnsNil() {
        XCTAssertNil(ytd(
            [stamp(2025, 12, 31), stamp(2026, 7, 27)],
            [nil, nil]
        ))
    }

    func testEmptySeriesReturnsNil() {
        XCTAssertNil(ytd([], []))
    }

    func testTimestampsWithoutMatchingClosesReturnNil() {
        // Yahoo has been seen returning a shorter close array; the extra
        // timestamps must not be read as points.
        XCTAssertNil(ytd([stamp(2025, 12, 31), stamp(2026, 7, 27)], []))
    }
}
