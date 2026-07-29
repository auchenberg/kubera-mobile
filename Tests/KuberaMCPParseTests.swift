import XCTest

/// Exercises the full parsing path from a raw tools/call response body to
/// history points, across every response variant a streamable-HTTP MCP server
/// can legally produce. These fixtures mirror real Kubera responses captured
/// live (JSON envelope, error envelope) plus the spec-permitted variants that
/// only show up intermittently in production (SSE framing, structuredContent).
final class KuberaMCPParseTests: XCTestCase {
    private let historyJSON =
        #"{\"portfolioId\":\"x\",\"portfolioDataPoints\":[{\"date\":\"2026-07-27\",\"value\":1190000.5},{\"date\":\"2026-07-28\",\"value\":1200000.25}]}"#

    private func parse(_ body: String) -> [KuberaAPI.HistoryPoint]? {
        KuberaMCP.parsePoints(fromToolResponse: Data(body.utf8))
    }

    func testPlainJSONEnvelopeWithTextContent() throws {
        let body = #"{"jsonrpc":"2.0","id":1,"result":{"isError":false,"content":[{"type":"text","text":"\#(historyJSON)"}]}}"#
        let points = try XCTUnwrap(parse(body))
        XCTAssertEqual(points.map(\.date), ["2026-07-27", "2026-07-28"])
    }

    func testSSEFramedEnvelope() throws {
        let body = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\(historyJSON)\"}]}}\n\n"
        let points = try XCTUnwrap(parse(body))
        XCTAssertEqual(points.count, 2)
    }

    func testSSEWithLeadingPingEventStillParses() throws {
        let body = ": ping\n\nevent: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\(historyJSON)\"}]}}\n\n"
        let points = try XCTUnwrap(parse(body))
        XCTAssertEqual(points.count, 2)
    }

    func testStructuredContentPayload() throws {
        let body = #"{"jsonrpc":"2.0","id":1,"result":{"isError":false,"content":[{"type":"text","text":"Here is your portfolio history."}],"structuredContent":{"portfolioId":"x","portfolioDataPoints":[{"date":"2026-07-27","value":1190000.5}]}}}"#
        let points = try XCTUnwrap(parse(body))
        XCTAssertEqual(points.map(\.date), ["2026-07-27"])
    }

    func testErrorEnvelopeReturnsNil() {
        let body = #"{"result":{"content":[{"type":"text","text":"{\"error\":\"Kubera MCP: Invalid Token\"}"}],"isError":true},"jsonrpc":"2.0","id":null}"#
        XCTAssertNil(parse(body))
    }

    func testMarkdownTextContentReturnsNil() {
        let body = ##"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"# Portfolio\n\n| Metric | Value |\n| --- | --- |"}]}}"##
        XCTAssertNil(parse(body))
    }

    func testGarbageBodyReturnsNil() {
        XCTAssertNil(parse("<html>502 Bad Gateway</html>"))
        XCTAssertNil(parse(""))
    }
}
