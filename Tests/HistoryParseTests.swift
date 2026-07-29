import XCTest

final class HistoryParseTests: XCTestCase {
    private func parse(_ json: String) -> [KuberaAPI.HistoryPoint]? {
        KuberaAPI.parseHistory(Data(json.utf8))
    }

    func testParsesBareArray() throws {
        let points = try XCTUnwrap(parse(
            #"[{"date":"2026-07-28","value":1200000.25,"assetTotal":1250000.5,"debtTotal":50000.75}]"#
        ))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].date, "2026-07-28")
        XCTAssertEqual(try XCTUnwrap(points[0].value), 1_200_000.25, accuracy: 0.01)
    }

    func testParsesDataWrappedPortfolioDataPoints() throws {
        let points = try XCTUnwrap(parse(
            #"{"data":{"portfolioDataPoints":[{"date":"2026-07-27","value":1}]}}"#
        ))
        XCTAssertEqual(points.map(\.date), ["2026-07-27"])
    }

    func testParsesChartAndCagrShape() throws {
        let points = try XCTUnwrap(parse(
            #"{"data":{"portfolioId":"x","portfolioDataPoints":{"groupByDay":{"currency":"USD","netWorth":[{"date":"2026-06-27","value":1180000.5,"rvValue":1180000.5}]}}}}"#
        ))
        XCTAssertEqual(points.map(\.date), ["2026-06-27"])
    }

    func testRejectsGarbage() {
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse(#"{"data":[]}"#))
        XCTAssertNil(parse(#"{"unrelated":true}"#))
    }
}
