import XCTest

/// Covers `Kubera.Parse` — the SDK's whole decoding surface, JSON and markdown.
///
/// Every fixture here is invented. The markdown mirrors the *shape* of a real
/// Kubera MCP payload (a `## Summary` metric table, a pipe-packed header line,
/// per-section holdings tables with a combined `Sheet > Section` column) at a
/// made-up $1.2M scale.
final class KuberaSDKTests: XCTestCase {
    // MARK: - Fixtures

    /// A well-formed portfolio payload with every summary metric present.
    private let portfolioMarkdown = """
    # Portfolio: Sample

    Currency: USD | Generated: 2026-07-28T12:00:00.000Z

    ## Summary

    | Metric | Value |
    | ---- | ---: |
    | Net Worth | 1,240,000 |
    | Total Assets | 1,610,000 |
    | Total Debt | 370,000 |
    | Cash On Hand | 74,000 |
    | Total Estimated Tax | 38,500 |
    | Cost Basis | 1,026,000 |
    | Unrealized Gain | 214,000 |

    ## Asset Allocation

    | Asset Class | % of Assets |
    | ---- | ---: |
    | Investment | 62.4 |
    | Real Estate | 28.0 |

    ## Concentration

    | Metric | Value (USD) | % of Assets |
    | ---- | ---: | ---: |
    | Top 3 Holdings | 1,166,000 | 72.4 |

    ## Top Holdings

    | Name | Value (USD) | % | Asset Class | Ticker | Sheet > Section |
    | ---- | ---: | ---: | ---- | ---- | ---- |
    | Index funds | 620,000 | 38.5 | investment | VTI | Investments > Brokerage |
    | Home | 450,000 | 28.0 | real estate |  | Real Estate > Primary |
    | Bitcoin | 96,000 | 6.0 | crypto | BTC |  |
    | Others (12 positions) | 44,000 | 2.7 | - | - | - |

    ## Investable Assets

    Total Investable: 790,000 USD (49.1% of assets)

    | Name | Value (USD) | % of Investable | Asset Class | Ticker | Sheet > Section |
    | ---- | ---: | ---: | ---- | ---- | ---- |
    | Index funds | 620,000 | 78.5 | investment | VTI | Investments > Brokerage |
    | Cash | 74,000 | 9.4 | cash |  | Banks > Checking |

    ## Debts

    | ID | Name | Value | Ticker | Since | Sheet | Section |
    | ---- | ---- | ---: | ---- | ---- | ---- | ---- |
    | d-1 | Mortgage | 340,000 | USD | 2019-04-01 | Loans | Section 1 |
    """

    private func detail(_ markdown: String) -> PortfolioDetail? {
        Kubera.Parse.detail(fromToolText: markdown)
    }

    // MARK: - Numbers

    func testNumberReadsThousandsSeparatorsAndCurrency() {
        XCTAssertEqual(Kubera.Parse.number("1,234,567.89"), 1_234_567.89)
        XCTAssertEqual(Kubera.Parse.number("$1,234"), 1234)
        XCTAssertEqual(Kubera.Parse.number("1,240,000 USD"), 1_240_000)
        XCTAssertEqual(Kubera.Parse.number("**38,500 USD**"), 38500)
        XCTAssertEqual(Kubera.Parse.number("12.5%"), 12.5)
        XCTAssertEqual(Kubera.Parse.number("790,000 USD (49.1% of assets)"), 790_000)
    }

    func testNumberReadsNegativesInBothSpellings() {
        XCTAssertEqual(Kubera.Parse.number("(1,234)"), -1234)
        XCTAssertEqual(Kubera.Parse.number("-45.2"), -45.2)
        XCTAssertEqual(Kubera.Parse.number("\u{2212}45.2"), -45.2)
    }

    func testNumberTreatsPlaceholdersAsMissingNotZero() {
        for placeholder in ["", "   ", "—", "-", "n/a", "N/A", "\u{2212}"] {
            XCTAssertNil(Kubera.Parse.number(placeholder), "\(placeholder) should read as missing")
        }
        XCTAssertNil(Kubera.Parse.number(nil))
        XCTAssertNil(Kubera.Parse.number("1.2.3"))
    }

    // MARK: - Summary table

    func testSummaryTableYieldsEveryMetric() throws {
        let detail = try XCTUnwrap(detail(portfolioMarkdown))
        XCTAssertEqual(detail.netWorth, 1_240_000)
        XCTAssertEqual(detail.assetTotal, 1_610_000)
        XCTAssertEqual(detail.debtTotal, 370_000)
        XCTAssertEqual(detail.cashOnHand, 74000)
        XCTAssertEqual(detail.estimatedTax, 38500)
        XCTAssertEqual(detail.costBasis, 1_026_000)
        XCTAssertEqual(detail.unrealizedGain, 214_000)
        XCTAssertEqual(detail.investableTotal, 790_000)
        XCTAssertEqual(detail.currency, "USD")
    }

    /// Kubera omits Cash On Hand entirely when it is zero. An absent metric has
    /// to stay absent: 0 would be a claim the payload never made.
    func testAbsentCashOnHandIsNilNotZero() throws {
        let trimmed = portfolioMarkdown
            .replacingOccurrences(of: "| Cash On Hand | 74,000 |\n", with: "")
            .replacingOccurrences(of: "| Total Estimated Tax | 38,500 |\n", with: "")
        let detail = try XCTUnwrap(detail(trimmed))
        XCTAssertNil(detail.cashOnHand)
        XCTAssertNil(detail.estimatedTax)
        XCTAssertEqual(detail.netWorth, 1_240_000)
    }

    func testGeneratedTimestampBecomesUpdatedAt() throws {
        let detail = try XCTUnwrap(detail(portfolioMarkdown))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-28T12:00:00Z"))
        XCTAssertEqual(detail.updatedAt, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testMissingGeneratedLineFallsBackToNow() throws {
        let stripped = portfolioMarkdown.replacingOccurrences(
            of: "Currency: USD | Generated: 2026-07-28T12:00:00.000Z",
            with: "Currency: USD"
        )
        let detail = try XCTUnwrap(detail(stripped))
        XCTAssertEqual(detail.currency, "USD")
        XCTAssertEqual(detail.updatedAt, Date().timeIntervalSince1970, accuracy: 5)
    }

    // MARK: - Assets

    func testAssetTableSplitsSheetAndSection() throws {
        let detail = try XCTUnwrap(detail(portfolioMarkdown))
        XCTAssertEqual(detail.assets.count, 4)

        let first = try XCTUnwrap(detail.assets.first)
        XCTAssertEqual(first.name, "Index funds")
        XCTAssertEqual(first.value, 620_000)
        XCTAssertEqual(first.assetClass, "investment")
        XCTAssertEqual(first.ticker, "VTI")
        XCTAssertEqual(first.sheet, "Investments")
        XCTAssertEqual(first.section, "Brokerage")
    }

    func testAssetWithoutSheetSectionOrTickerYieldsNils() throws {
        let detail = try XCTUnwrap(detail(portfolioMarkdown))
        let bitcoin = try XCTUnwrap(detail.assets.first { $0.name == "Bitcoin" })
        XCTAssertNil(bitcoin.sheet)
        XCTAssertNil(bitcoin.section)
        XCTAssertEqual(bitcoin.ticker, "BTC")

        // Kubera writes "-" in the columns of its rolled-up remainder row.
        let others = try XCTUnwrap(detail.assets.first { $0.name.hasPrefix("Others") })
        XCTAssertNil(others.assetClass)
        XCTAssertNil(others.ticker)
        XCTAssertNil(others.sheet)
        XCTAssertNil(others.section)
        XCTAssertEqual(others.value, 44000)

        let home = try XCTUnwrap(detail.assets.first { $0.name == "Home" })
        XCTAssertNil(home.ticker)
        XCTAssertEqual(home.sheet, "Real Estate")
        XCTAssertEqual(home.section, "Primary")
    }

    /// The separate `Sheet` and `Section` columns of the full `## Assets` table,
    /// used when there is no ranked Top Holdings section.
    func testSeparateSheetAndSectionColumns() throws {
        let markdown = """
        ## Summary

        | Metric | Value |
        | ---- | ---: |
        | Net Worth | 1,200,000 |

        ## Assets

        | ID | Name | Cash | Currency | Value | Ticker | Asset Class | Sheet | Section |
        | ---- | ---- | ---- | ---- | ---: | ---- | ---- | ---- | ---- |
        | a-1 | Brokerage | | USD | 900,000 | VTI | investment | Investments | Taxable |
        | a-2 | Checking | Yes | USD | 300,000 | | cash | Banks | Section 1 |
        """
        let detail = try XCTUnwrap(detail(markdown))
        XCTAssertEqual(detail.assets.map(\.name), ["Brokerage", "Checking"])
        XCTAssertEqual(detail.assets.map(\.sheet), ["Investments", "Banks"])
        XCTAssertEqual(detail.assets.map(\.section), ["Taxable", "Section 1"])
        XCTAssertEqual(detail.assets.last?.value, 300_000)
    }

    func testSplitSheetSectionHandlesPartialAndMissingCells() {
        XCTAssertEqual(Kubera.Parse.splitSheetSection("Investments > Brokerage").sheet, "Investments")
        XCTAssertEqual(Kubera.Parse.splitSheetSection("Investments > Brokerage").section, "Brokerage")
        XCTAssertEqual(Kubera.Parse.splitSheetSection("Investments").sheet, "Investments")
        XCTAssertNil(Kubera.Parse.splitSheetSection("Investments").section)
        XCTAssertNil(Kubera.Parse.splitSheetSection("Investments >").section)
        XCTAssertNil(Kubera.Parse.splitSheetSection("—").sheet)
        XCTAssertNil(Kubera.Parse.splitSheetSection(nil).sheet)
        XCTAssertNil(Kubera.Parse.splitSheetSection(nil).section)
    }

    // MARK: - Damaged input

    /// Rows that are short, over-wide, valueless or unnamed are dropped; the
    /// readable rows still come through, and nothing traps.
    func testMalformedRowsAreSkipped() throws {
        let markdown = """
        # Portfolio: Sample

        ## Summary

        | Metric | Value |
        | Net Worth | 1,200,000 |
        | Total Assets |
        | | 42 |

        ## Top Holdings

        | Name | Value (USD) | % | Asset Class | Ticker | Sheet > Section |
        | Index funds | 620,000 | 38.5 | investment | VTI | Investments > Brokerage | extra | cells |
        | Broken row
        | No value | — | | | | |
        |  | 12,000 | | | | |
        """
        let detail = try XCTUnwrap(detail(markdown))
        XCTAssertEqual(detail.netWorth, 1_200_000)
        XCTAssertNil(detail.assetTotal)
        XCTAssertEqual(detail.assets.map(\.name), ["Index funds"])
        XCTAssertEqual(detail.assets.first?.sheet, "Investments")
    }

    func testGarbageAndEmptyInputYieldNil() {
        XCTAssertNil(detail(""))
        XCTAssertNil(detail("<html>502 Bad Gateway</html>"))
        XCTAssertNil(detail("Sorry, I could not find that portfolio."))
        XCTAssertNil(detail("# Portfolio: Sample\n\nCurrency: USD\n\nNo tables here.\n"))
        XCTAssertNil(Kubera.Parse.profile(fromToolText: "<html>502</html>"))
        XCTAssertNil(Kubera.Parse.profile(fromToolText: ""))
    }

    // MARK: - Tool payload wrappers

    /// Kubera returns the markdown inside a JSON object rather than bare.
    func testDetailUnwrapsJSONWrappedMarkdown() throws {
        let wrapper: [String: Any] = [
            "defaultPortfolio": [
                "id": "portfolio-1",
                "name": "Sample",
                "currency": "USD",
                "markdown": portfolioMarkdown,
            ],
            "otherPortfolios": [],
        ]
        let text = try XCTUnwrap(
            String(data: try JSONSerialization.data(withJSONObject: wrapper), encoding: .utf8)
        )
        let detail = try XCTUnwrap(detail(text))
        XCTAssertEqual(detail.netWorth, 1_240_000)
        XCTAssertEqual(detail.assets.count, 4)
    }

    func testProfileFromJSONAndFromMarkdown() throws {
        let json = #"{"profile":{"name":"Sample User","email":"sample@example.com"}}"#
        let fromJSON = try XCTUnwrap(Kubera.Parse.profile(fromToolText: json))
        XCTAssertEqual(fromJSON.name, "Sample User")
        XCTAssertEqual(fromJSON.email, "sample@example.com")

        let markdown = "# Profile\n\n- Name: Sample User\n- Email: sample@example.com\n"
        XCTAssertEqual(Kubera.Parse.profile(fromToolText: markdown), fromJSON)

        // Neither field present: no profile rather than an empty card.
        XCTAssertNil(Kubera.Parse.profile(fromToolText: #"{"plan":"pro"}"#))
    }

    // MARK: - Codable round-trip

    func testPortfolioDetailRoundTripsThroughJSON() throws {
        let original = try XCTUnwrap(detail(portfolioMarkdown))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PortfolioDetail.self, from: encoded)
        XCTAssertEqual(decoded, original)

        let profile = KuberaProfile(name: "Sample User", email: nil)
        let decodedProfile = try JSONDecoder().decode(
            KuberaProfile.self,
            from: try JSONEncoder().encode(profile)
        )
        XCTAssertEqual(decodedProfile, profile)
    }

    // MARK: - MCP envelope

    private let historyJSON =
        #"{\"portfolioId\":\"x\",\"portfolioDataPoints\":[{\"date\":\"2026-07-27\",\"value\":1190000.5},{\"date\":\"2026-07-28\",\"value\":1200000.25}]}"#

    private func points(_ body: String) -> [Kubera.HistoryPoint]? {
        Kubera.Parse.historyPoints(inToolResponse: Data(body.utf8))
    }

    func testPlainJSONEnvelope() throws {
        let body = #"{"jsonrpc":"2.0","id":1,"result":{"isError":false,"content":[{"type":"text","text":"\#(historyJSON)"}]}}"#
        XCTAssertEqual(try XCTUnwrap(points(body)).map(\.date), ["2026-07-27", "2026-07-28"])
    }

    func testSSEFramedEnvelope() throws {
        let body = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\(historyJSON)\"}]}}\n\n"
        XCTAssertEqual(try XCTUnwrap(points(body)).count, 2)
    }

    func testSSEWithLeadingPingStillParses() throws {
        let body = ": ping\n\nevent: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\(historyJSON)\"}]}}\n\n"
        XCTAssertEqual(try XCTUnwrap(points(body)).count, 2)
    }

    func testStructuredContentPayload() throws {
        let body = #"{"jsonrpc":"2.0","id":1,"result":{"isError":false,"content":[{"type":"text","text":"Here is your portfolio history."}],"structuredContent":{"portfolioId":"x","portfolioDataPoints":[{"date":"2026-07-27","value":1190000.5}]}}}"#
        XCTAssertEqual(try XCTUnwrap(points(body)).map(\.date), ["2026-07-27"])
    }

    func testErrorEnvelopeYieldsNoPointsAndReadableErrorText() {
        let body = #"{"result":{"content":[{"type":"text","text":"{\"error\":\"Kubera MCP: Invalid Token\"}"}],"isError":true},"jsonrpc":"2.0","id":null}"#
        XCTAssertNil(points(body))
        XCTAssertNil(Kubera.Parse.toolText(in: Data(body.utf8)))
        XCTAssertEqual(Kubera.Parse.errorText(in: Data(body.utf8)), "Kubera MCP: Invalid Token")
    }

    func testToolTextReturnsTheMarkdownPayload() throws {
        let body = ##"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"# Portfolio\n\n| Metric | Value |"}]}}"##
        let text = try XCTUnwrap(Kubera.Parse.toolText(in: Data(body.utf8)))
        XCTAssertTrue(text.hasPrefix("# Portfolio"))
        // Markdown is not a history payload, so the history path must decline it.
        XCTAssertNil(points(body))
    }

    func testGarbageEnvelopeYieldsNil() {
        XCTAssertNil(points("<html>502 Bad Gateway</html>"))
        XCTAssertNil(points(""))
        XCTAssertNil(Kubera.Parse.toolText(in: Data()))
        XCTAssertNil(Kubera.Parse.errorText(in: Data()))
    }

    func testTokenSanitisingStripsPastedScheme() {
        XCTAssertEqual(Kubera.Parse.sanitizedToken("Basic abc123"), "abc123")
        XCTAssertEqual(Kubera.Parse.sanitizedToken("  basic   abc123  "), "abc123")
        XCTAssertEqual(Kubera.Parse.sanitizedToken("abc123"), "abc123")
        XCTAssertNil(Kubera.Parse.sanitizedToken("   "))
        XCTAssertNil(Kubera.Parse.sanitizedToken("Basic "))
        XCTAssertNil(Kubera.Parse.sanitizedToken(nil))
    }

    // MARK: - History response shapes

    private func history(_ json: String) -> [Kubera.HistoryPoint]? {
        Kubera.Parse.history(Data(json.utf8))
    }

    func testHistoryParsesBareArray() throws {
        let points = try XCTUnwrap(history(
            #"[{"date":"2026-07-28","value":1200000.25,"assetTotal":1250000.5,"debtTotal":50000.75}]"#
        ))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(try XCTUnwrap(points[0].value), 1_200_000.25, accuracy: 0.01)
    }

    func testHistoryParsesDataWrappedPoints() throws {
        let points = try XCTUnwrap(history(#"{"data":{"portfolioDataPoints":[{"date":"2026-07-27","value":1}]}}"#))
        XCTAssertEqual(points.map(\.date), ["2026-07-27"])
    }

    func testHistoryParsesChartAndCagrNesting() throws {
        let points = try XCTUnwrap(history(
            #"{"data":{"portfolioId":"x","portfolioDataPoints":{"groupByDay":{"currency":"USD","netWorth":[{"date":"2026-06-27","value":1180000.5,"rvValue":1180000.5}]}}}}"#
        ))
        XCTAssertEqual(points.map(\.date), ["2026-06-27"])
    }

    func testHistoryRejectsGarbage() {
        XCTAssertNil(history("not json"))
        XCTAssertNil(history(#"{"data":[]}"#))
        XCTAssertNil(history(#"{"unrelated":true}"#))
    }

    // MARK: - Error mapping

    func testHTTPStatusMapping() {
        XCTAssertNil(Kubera.Error.from(httpStatus: 200))
        XCTAssertNil(Kubera.Error.from(httpStatus: 204))
        XCTAssertEqual(Kubera.Error.from(httpStatus: 401)?.errorDescription,
                       Kubera.Error.unauthorized.errorDescription)
        XCTAssertEqual(Kubera.Error.from(httpStatus: 429)?.errorDescription,
                       Kubera.Error.rateLimited.errorDescription)
        XCTAssertEqual(Kubera.Error.from(httpStatus: 503)?.errorDescription,
                       Kubera.Error.badResponse(status: 503).errorDescription)
    }
}
