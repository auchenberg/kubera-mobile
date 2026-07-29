import Foundation
import os

/// Client for Kubera's MCP endpoint — the one API-key-accessible surface that
/// serves portfolio history (the REST paths 404 or reject key auth).
///
/// `api.kubera.com/api/v2/mcp` is stateless JSON-RPC over a single POST with
/// `Authorization: Basic <token>`; no MCP session handshake is required, and
/// tool results come back as a JSON string inside `result.content[0].text`.
enum KuberaMCP {
    private static let endpoint = "https://api.kubera.com/api/v2/mcp"
    private static let log = Logger(subsystem: "com.auchenberg.kuberawidgets", category: "api")

    /// Fetches the portfolio's value history via the `get_portfolio_history`
    /// MCP tool. Requires the dedicated MCP token — the endpoint rejects the
    /// REST API key ("Kubera MCP: Invalid apiKey", verified live), so without
    /// a token this returns nil immediately.
    ///
    /// Every outcome is mirrored into `SharedStore.setHistoryStatus` so the
    /// Settings card can show what actually happened on the last attempt.
    static func fetchHistory(creds: KuberaCredentials, portfolioId: String) async -> [KuberaAPI.HistoryPoint]? {
        guard let token = sanitized(creds.mcpToken), !token.isEmpty else {
            SharedStore.setHistoryStatus("No MCP token saved — growth builds from the on-device log instead.")
            return nil
        }
        return await callHistory(token: token, portfolioId: portfolioId)
    }

    /// Kubera's docs show the header as "Basic AUTH_TOKEN"; people paste the
    /// whole thing. Strip the scheme so we don't send "Basic Basic …".
    private static func sanitized(_ token: String?) -> String? {
        guard var token = token?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if token.lowercased().hasPrefix("basic ") {
            token = String(token.dropFirst("basic ".count)).trimmingCharacters(in: .whitespaces)
        }
        return token
    }

    private static func callHistory(token: String, portfolioId: String) async -> [KuberaAPI.HistoryPoint]? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "get_portfolio_history",
                "arguments": ["portfolioId": portfolioId],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            log.info("mcp history: request failed")
            SharedStore.setHistoryStatus("History fetch failed: network error.")
            return nil
        }
        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            log.info("mcp history: HTTP \(http.statusCode): \(body, privacy: .public)")
            SharedStore.setHistoryStatus("History fetch failed (HTTP \(http.statusCode)): \(errorText(in: data) ?? "unknown error")")
            return nil
        }

        guard let points = parsePoints(fromToolResponse: data), !points.isEmpty else {
            let detail = errorText(in: data)
                ?? String(data: data.prefix(120), encoding: .utf8).map { "body: \($0)" }
                ?? "empty body"
            log.info("mcp history: 200 but no usable payload (\(detail, privacy: .public))")
            SharedStore.setHistoryStatus("History fetch failed: Kubera answered but the payload was unreadable (\(detail)).")
            return nil
        }
        log.info("mcp history: got \(points.count) points")
        SharedStore.setHistoryStatus("History: \(points.count) points from Kubera's API.")
        return points
    }

    /// Pure parsing path from a raw tools/call response body to history points,
    /// so every server variant is unit-testable without a network. Handles
    /// plain-JSON and SSE-framed envelopes, payloads in `content[].text`, and
    /// payloads in the spec's `structuredContent` field.
    static func parsePoints(fromToolResponse data: Data) -> [KuberaAPI.HistoryPoint]? {
        guard let envelope = decodeEnvelope(data), envelope.result?.isError != true else {
            return nil
        }
        if let text = envelope.result?.content?.first(where: { $0.type == "text" })?.text,
           let points = KuberaAPI.parseHistory(Data(text.utf8)), !points.isEmpty {
            return points
        }
        if let structured = envelope.result?.structuredContent,
           let data = try? JSONSerialization.data(withJSONObject: structured.value),
           let points = KuberaAPI.parseHistory(data), !points.isEmpty {
            return points
        }
        return nil
    }

    /// Streamable-HTTP servers may answer a POST with plain JSON or with SSE
    /// framing ("event: message" / "data: {…}" lines). Try JSON first, then
    /// unwrap the data: lines and try again.
    private static func decodeEnvelope(_ data: Data) -> Envelope? {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope
        }
        guard let text = String(data: data, encoding: .utf8), text.contains("data:") else {
            return nil
        }
        let payload = text
            .split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst("data:".count).trimmingCharacters(in: .whitespaces) }
            .joined()
        return try? decoder.decode(Envelope.self, from: Data(payload.utf8))
    }

    /// Digs the human-readable error out of the JSON-RPC envelope, e.g.
    /// "Kubera MCP: Invalid Token".
    private static func errorText(in data: Data) -> String? {
        guard let envelope = decodeEnvelope(data),
              let text = envelope.result?.content?.first(where: { $0.type == "text" })?.text else {
            return nil
        }
        struct InnerError: Decodable { let error: String? }
        let inner = (try? JSONDecoder().decode(InnerError.self, from: Data(text.utf8)))?.error ?? text
        return String(inner.prefix(120))
    }

    // MARK: - JSON-RPC envelope

    private struct Envelope: Decodable {
        let result: ToolResult?
    }

    private struct ToolResult: Decodable {
        let isError: Bool?
        let content: [Content]?
        let structuredContent: JSONValue?
    }

    private struct Content: Decodable {
        let type: String?
        let text: String?
    }

    /// Decodes arbitrary JSON into Foundation objects so `structuredContent`
    /// (whose shape the server owns) can be re-serialized for parsing.
    private struct JSONValue: Decodable {
        let value: Any

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: JSONValue].self) {
                value = dict.mapValues(\.value)
            } else if let array = try? container.decode([JSONValue].self) {
                value = array.map(\.value)
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let number = try? container.decode(Double.self) {
                value = number
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                value = NSNull()
            }
        }
    }
}
