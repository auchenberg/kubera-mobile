import XCTest

/// Covers the `get_portfolio_cagr` reader in `Shared/KuberaCAGR.swift`.
///
/// Kubera publishes nothing about this tool's response, so every fixture here is
/// a *guess at a shape*, modeled on the payloads the verified tools return (an
/// LLM-oriented markdown document with a `## Summary`-style table and a
/// pipe-packed header line) at the same invented $1.2M scale as the rest of the
/// suite. The tests are therefore two claims: that each plausible shape is read
/// correctly, and — the load-bearing half — that everything else is refused so
/// the Overview falls back to the rate it computes itself.
final class KuberaCAGRTests: XCTestCase {
    private func cagr(_ text: String) -> PortfolioCAGR? {
        Kubera.Parse.cagr(fromToolText: text, now: Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: - Markdown shapes

    func testReadsATableOfRatesByMetric() throws {
        let payload = """
        # Portfolio: Sample

        Currency: USD | Generated: 2026-07-28T12:00:00.000Z

        ## CAGR

        | Metric | CAGR | Since |
        | ---- | ---: | ---- |
        | Net Worth | 12.4% | 2019-04-01 |
        | Investable Assets | 15.1% | 2019-04-01 |
        """
        let cagr = try XCTUnwrap(cagr(payload))
        XCTAssertEqual(try XCTUnwrap(cagr.netWorth), 12.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cagr.investable), 15.1, accuracy: 0.001)

        let generated = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-28T12:00:00Z"))
        XCTAssertEqual(cagr.updatedAt, generated.timeIntervalSince1970, accuracy: 1)
    }

    /// A table by horizon rather than by metric. The dashboard's figure is the
    /// since-inception one, so that is the row that stands for net worth.
    func testReadsATableOfRatesByPeriod() throws {
        let payload = """
        ## CAGR

        | Period | CAGR |
        | ---- | ---: |
        | 1Y | 8.1% |
        | 3Y | 10.9% |
        | All Time | 12.4% |
        """
        let cagr = try XCTUnwrap(cagr(payload))
        XCTAssertEqual(try XCTUnwrap(cagr.netWorth), 12.4, accuracy: 0.001)
        XCTAssertNil(cagr.investable)
    }

    func testReadsALabelledLine() throws {
        let payload = """
        # Portfolio: Sample

        CAGR: 12.4%
        """
        XCTAssertEqual(try XCTUnwrap(cagr(payload)?.netWorth), 12.4, accuracy: 0.001)
    }

    func testReadsASummaryRow() throws {
        let payload = """
        | Metric | Value |
        | ---- | ---: |
        | Net Worth | 1,240,000 |
        | Net Worth CAGR | 12.4% |
        """
        XCTAssertEqual(try XCTUnwrap(cagr(payload)?.netWorth), 12.4, accuracy: 0.001)
    }

    /// The one-sentence answer, which is a real possibility for a tool whose
    /// whole job is a single number.
    func testReadsAPercentageOutOfProse() throws {
        let payload = "The CAGR for this portfolio is 12.4% since April 2019."
        XCTAssertEqual(try XCTUnwrap(cagr(payload)?.netWorth), 12.4, accuracy: 0.001)
    }

    func testReadsANegativeRate() throws {
        XCTAssertEqual(try XCTUnwrap(cagr("CAGR: -4.2%")?.netWorth), -4.2, accuracy: 0.001)
    }

    /// The wrapper `get_default_portfolio` uses: markdown inside a JSON object.
    func testReadsMarkdownWrappedInJSON() throws {
        // Three-hash delimiters: the markdown inside carries `"##`, which would
        // close a shorter raw-string literal.
        let payload = ###"{"defaultPortfolio":{"id":"p-1","markdown":"## CAGR\n\nCAGR: 12.4%\n"}}"###
        XCTAssertEqual(try XCTUnwrap(cagr(payload)?.netWorth), 12.4, accuracy: 0.001)
    }

    // MARK: - Structured shapes

    func testReadsAStructuredPayloadByKeyName() throws {
        let payload = #"{"data":{"portfolioId":"p-1","cagrPercent":12.4,"investableCagr":15.1}}"#
        let cagr = try XCTUnwrap(cagr(payload))
        XCTAssertEqual(try XCTUnwrap(cagr.netWorth), 12.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cagr.investable), 15.1, accuracy: 0.001)
    }

    func testReadsARateNestedUnderItsOwnObject() throws {
        let payload = #"{"cagr":{"netWorth":12.4,"investable":15.1}}"#
        let cagr = try XCTUnwrap(cagr(payload))
        XCTAssertEqual(try XCTUnwrap(cagr.netWorth), 12.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cagr.investable), 15.1, accuracy: 0.001)
    }

    /// A percent-named key settles the spelling question, so a sub-1 value under
    /// it is read rather than refused.
    func testAPercentNamedKeyIsTrustedBelowOne() throws {
        XCTAssertEqual(try XCTUnwrap(cagr(#"{"cagrPercent":0.4}"#)?.netWorth), 0.4, accuracy: 0.001)
    }

    // MARK: - Refusals
    //
    // Each of these must come back as "no figure" rather than a wrong one: the
    // growth block then prints the rate it computed itself, exactly as it did
    // before this tool was ever called.

    /// The unresolved question this whole file is careful about: 0.124 is either
    /// a 12.4% year or a 0.124% one, and nothing in the payload says which.
    func testABareFractionIsRefusedAsAmbiguous() {
        XCTAssertNil(cagr(#"{"cagr":0.124}"#))
        XCTAssertNil(Kubera.Parse.cagrPercent(0.124, statedAsPercentage: false))
        XCTAssertEqual(Kubera.Parse.cagrPercent(0.124, statedAsPercentage: true), 0.124)
    }

    /// A bare number of 1 or more can only sensibly be a percentage.
    func testABareNumberAtOrAboveOneIsAPercentage() {
        XCTAssertEqual(Kubera.Parse.cagrPercent(12.4, statedAsPercentage: false), 12.4)
        XCTAssertEqual(Kubera.Parse.cagrPercent(-12.4, statedAsPercentage: false), -12.4)
        XCTAssertEqual(Kubera.Parse.cagrPercent(0, statedAsPercentage: false), 0)
    }

    /// The guard that keeps a misread column off the card: an amount parked in a
    /// CAGR cell is not a rate anyone has.
    func testAnImplausibleRateIsRefused() {
        XCTAssertNil(cagr("| Metric | CAGR |\n| ---- | ---: |\n| Net Worth | 1,240,000 |"))
        XCTAssertNil(Kubera.Parse.cagrPercent(1_240_000, statedAsPercentage: true))
        XCTAssertNil(Kubera.Parse.cagrPercent(-101, statedAsPercentage: true))
        XCTAssertNil(Kubera.Parse.cagrPercent(.nan, statedAsPercentage: true))
        XCTAssertNil(Kubera.Parse.cagrPercent(.infinity, statedAsPercentage: true))
    }

    /// A portfolio payload that says nothing about CAGR must not have one read
    /// out of its net worth or its allocation percentages.
    func testAPortfolioPayloadWithoutARateYieldsNothing() {
        let payload = """
        # Portfolio: Sample

        Currency: USD | Generated: 2026-07-28T12:00:00.000Z

        ## Summary

        | Metric | Value |
        | ---- | ---: |
        | Net Worth | 1,240,000 |
        | Total Assets | 1,610,000 |

        ## Asset Allocation

        | Asset Class | % of Assets |
        | ---- | ---: |
        | Investment | 62.4 |
        """
        XCTAssertNil(cagr(payload))
    }

    func testAnErrorOrEmptyPayloadYieldsNothing() {
        XCTAssertNil(cagr(""))
        XCTAssertNil(cagr(#"{"error":"Kubera MCP: Invalid Token"}"#))
        XCTAssertNil(cagr("Unknown tool: get_portfolio_cagr"))
        XCTAssertNil(cagr("| Metric | CAGR |\n| ---- | ---: |\n| Net Worth | — |"))
    }

    // MARK: - The fallback the screen relies on

    func testKuberasFigureWinsAndAMissingOneFallsBackToTheComputedRate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        let series = [
            ChartPoint(date: start, value: 1_000_000),
            ChartPoint(date: calendar.date(byAdding: .year, value: 2, to: start)!, value: 1_440_000),
        ]
        let computed = try XCTUnwrap(OverviewModules.cagrPercent(in: series))
        XCTAssertEqual(computed, 20, accuracy: 0.1, "√1.44 − 1 a year")

        XCTAssertEqual(OverviewModules.cagrPercent(kubera: 12.4, in: series), 12.4)
        XCTAssertEqual(OverviewModules.cagrPercent(kubera: nil, in: series), computed)
    }

    /// The case that only Kubera can answer: a device that has been logging for
    /// three weeks has no computed rate at all, and printing "—" beside a YTD
    /// figure is what this integration removes.
    func testKuberasFigureShowsEvenWhenTheSeriesIsTooShortToComputeOne() {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        let series = [
            ChartPoint(date: start, value: 1_000_000),
            ChartPoint(date: start.addingTimeInterval(21 * 24 * 60 * 60), value: 1_020_000),
        ]
        XCTAssertNil(OverviewModules.cagrPercent(in: series))
        XCTAssertEqual(OverviewModules.cagrPercent(kubera: 12.4, in: series), 12.4)
    }

    // MARK: - What a refresh costs
    //
    // The argument spelling is unverified, so the fetch may have to ask three
    // ways. These are the rules that keep it from asking three ways forever.

    private let probeKeys = ["portfolioId", "id", ""]

    private func order(after probe: KuberaCAGRProbe?, secondsLater: TimeInterval = 0) -> [String] {
        Kubera.MCP.cagrProbeOrder(
            after: probe,
            keys: probeKeys,
            now: Date(timeIntervalSince1970: 1_780_000_000 + secondsLater)
        )
    }

    func testAFirstFetchTriesEverySpelling() {
        XCTAssertEqual(order(after: nil), probeKeys)
    }

    func testARememberedSpellingIsTheOnlyOneTried() {
        XCTAssertEqual(order(after: KuberaCAGRProbe(answered: "id", failedAt: nil)), ["id"])
    }

    /// The no-argument call is a real answer, and `""` has to be tellable from
    /// "nothing is remembered".
    func testTheNoArgumentCallIsRemembered() {
        XCTAssertEqual(order(after: KuberaCAGRProbe(answered: "", failedAt: nil)), [""])
    }

    /// A memo naming a spelling this build no longer offers must not leave the
    /// fetch with nothing to ask.
    func testAnUnknownRememberedSpellingFallsBackToTheFullSweep() {
        XCTAssertEqual(order(after: KuberaCAGRProbe(answered: "portfolio_id", failedAt: nil)), probeKeys)
    }

    func testASweepThatFoundNothingStandsTheFetchDown() {
        let failed = KuberaCAGRProbe(answered: nil, failedAt: 1_780_000_000)
        XCTAssertEqual(order(after: failed), [], "no call at all while the failure is fresh")
        XCTAssertEqual(
            order(after: failed, secondsLater: Kubera.MCP.cagrProbeRetry + 1),
            probeKeys,
            "and a full retry once it has aged out"
        )
    }

    func testASpellingBuildsWithAndWithoutAPortfolioId() {
        XCTAssertEqual(Kubera.MCP.cagrAttempts(portfolioId: "p-1").map(\.key), probeKeys)
        XCTAssertEqual(
            Kubera.MCP.cagrAttempts(portfolioId: nil).map(\.key), [""],
            "with no portfolio to name, the only call left is the no-argument one"
        )
    }

    // MARK: - Cached shape

    func testTheCachedRecordSurvivesARoundTrip() throws {
        let cagr = PortfolioCAGR(netWorth: 12.4, investable: 15.1, updatedAt: 1_780_000_000)
        let data = try JSONEncoder().encode(cagr)
        XCTAssertEqual(try JSONDecoder().decode(PortfolioCAGR.self, from: data), cagr)
    }

    /// The demo run seeds the store from `DemoData` and never touches the
    /// network, so both growth rows need a served figure or the demo would be
    /// showing the fallback rather than the feature.
    func testTheDemoPortfolioCarriesBothServedRates() {
        XCTAssertFalse(DemoData.cagr.isEmpty)
        XCTAssertNotNil(DemoData.cagr.netWorth)
        XCTAssertNotNil(DemoData.cagr.investable)
    }

    func testARecordWithNoFiguresKnowsItIsEmpty() {
        XCTAssertTrue(PortfolioCAGR(netWorth: nil, investable: nil, updatedAt: 0).isEmpty)
        XCTAssertFalse(PortfolioCAGR(netWorth: 12.4, investable: nil, updatedAt: 0).isEmpty)
    }
}
