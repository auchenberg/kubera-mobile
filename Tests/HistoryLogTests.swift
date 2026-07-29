import XCTest

final class HistoryLogTests: XCTestCase {
    private func point(_ date: String, _ value: Double) -> KuberaAPI.HistoryPoint {
        KuberaAPI.HistoryPoint(
            date: date,
            value: value,
            assetTotal: nil,
            debtTotal: nil,
            investibleTotal: nil
        )
    }

    func testAppendsInDateOrder() {
        let series = HistoryLog.appending(
            point("2026-07-27", 2),
            to: [point("2026-07-26", 1), point("2026-07-28", 3)]
        )

        XCTAssertEqual(series.map(\.date), ["2026-07-26", "2026-07-27", "2026-07-28"])
    }

    func testSameDayReplacesTheEarlierPoint() {
        let series = HistoryLog.appending(
            point("2026-07-28", 200),
            to: [point("2026-07-27", 1), point("2026-07-28", 100)]
        )

        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.last?.value, 200)
    }

    func testDropsTheOldestBeyondTheCap() {
        // The log orders lexically, so zero-padded pseudo-dates keep the test
        // free of calendar arithmetic while staying unique and sorted.
        let full = (0 ..< HistoryLog.cap).map {
            point(String(format: "2024-%04d", $0), Double($0))
        }
        let series = HistoryLog.appending(point("2026-07-28", 1), to: full)

        XCTAssertEqual(series.count, HistoryLog.cap)
        XCTAssertEqual(series.last?.date, "2026-07-28")
        XCTAssertEqual(series.first?.date, "2024-0001", "the oldest point is dropped")
    }
}
