import CryptoKit
import Foundation
import os

// MARK: - Models served only by MCP

/// The signed-in Kubera user, as reported by the MCP `get_profile` tool.
struct KuberaProfile: Codable, Equatable {
    let name: String?
    let email: String?
}

/// Portfolio facts Kubera serves only through its MCP endpoint: the summary
/// metrics behind the dashboard cards plus the ranked holdings table. The REST
/// snapshot has none of cash on hand, estimated tax, or the investable total.
struct PortfolioDetail: Codable, Equatable {
    struct Asset: Codable, Equatable, Hashable {
        let name: String
        let value: Double
        let assetClass: String?
        let ticker: String?
        /// Left of the `>` in Kubera's combined "Sheet > Section" column.
        let sheet: String?
        let section: String?
    }

    let currency: String?
    let netWorth: Double?
    let assetTotal: Double?
    let debtTotal: Double?
    let cashOnHand: Double?
    let estimatedTax: Double?
    let investableTotal: Double?
    let costBasis: Double?
    let unrealizedGain: Double?
    let assets: [Asset]
    let updatedAt: Double
}

// MARK: - The SDK

/// Everything that talks to Kubera.
///
/// Two transports, because Kubera splits its data across them:
///
/// - `Kubera.REST` — `api.kubera.com/api/v3`, HMAC-signed with the API key and
///   secret. Serves the portfolio list and balances. Its history paths are
///   undocumented and have never answered in practice, but they are still
///   probed first because they are the supported, signed surface.
/// - `Kubera.MCP` — `api.kubera.com/api/v2/mcp`, stateless JSON-RPC over a
///   single POST authenticated with the separate "MCP Token". The only surface
///   that serves history, and the only one that serves the portfolio detail and
///   the user profile — as LLM-oriented markdown, which `Kubera.Parse` reads.
///
/// `Kubera.Parse` holds every decoder, JSON and markdown alike. Nothing in it
/// touches the network, so every response shape is unit-testable.
enum Kubera {
    typealias Credentials = KuberaCredentials

    fileprivate static let log = Logger(subsystem: "com.kubera.mobile", category: "api")

    /// One day of portfolio history. Every figure but the date is optional: the
    /// endpoint is undocumented and has been seen omitting fields. The extra
    /// `rv*` keys the web app's endpoint returns are ignored.
    ///
    /// The JSON shape is written to the on-device history log, so the property
    /// names are a storage format — renaming one orphans a user's log.
    struct HistoryPoint: Codable {
        let date: String // "yyyy-MM-dd"
        let value: Double? // net worth
        let assetTotal: Double?
        let debtTotal: Double?
        let investibleTotal: Double?
    }

    /// Every failure either transport can report. One error type, so callers
    /// (and `ConnectionStatus`) have one thing to switch on.
    enum Error: Swift.Error, LocalizedError {
        case badResponse(status: Int? = nil)
        case unauthorized
        case rateLimited
        case emptyPortfolio
        /// A credential the call needs was never saved — no request was made.
        case notConfigured

        var errorDescription: String? {
            switch self {
            case let .badResponse(status):
                guard let status else { return "Could not reach Kubera. Try again." }
                return "Kubera API error (HTTP \(status))."
            case .unauthorized:
                return "Authentication failed. Check your API key and secret."
            case .rateLimited:
                return "Kubera rate limit reached. Try again in a minute."
            case .emptyPortfolio:
                return "Kubera returned an empty portfolio."
            case .notConfigured:
                return "No Kubera MCP token saved."
            }
        }

        /// The single mapping from HTTP status to error, shared by both
        /// transports. nil for a success status.
        static func from(httpStatus status: Int) -> Error? {
            switch status {
            case 200 ..< 300: return nil
            case 401, 403: return .unauthorized
            case 429: return .rateLimited
            default: return .badResponse(status: status)
            }
        }
    }

    // MARK: - REST transport

    /// The HMAC-signed REST API: portfolio list and balances.
    enum REST {
        private static let baseURL = "https://api.kubera.com"

        /// Signs and performs one GET. Requests carry
        /// `HMAC-SHA256(apiKey + unixTimestamp + "GET" + path)` under the
        /// secret, alongside the key and the timestamp used to build it.
        private static func get(_ path: String, creds: Credentials) async throws -> Data {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let payload = "\(creds.apiKey)\(timestamp)GET\(path)"
            let key = SymmetricKey(data: Data(creds.secret.utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
                .map { String(format: "%02x", $0) }
                .joined()

            guard let url = URL(string: baseURL + path) else { throw Error.badResponse() }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(creds.apiKey, forHTTPHeaderField: "x-api-token")
            request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
            request.setValue(signature, forHTTPHeaderField: "x-signature")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Error.badResponse() }
            if let error = Error.from(httpStatus: http.statusCode) { throw error }
            return data
        }

        /// Lists the portfolios on the account, for the picker in settings.
        /// Returns an empty array when the account has none.
        static func listPortfolios(creds: Credentials) async throws -> [PortfolioListItem] {
            try Parse.portfolios(try await get("/api/v3/data/portfolio", creds: creds))
        }

        /// Fetches a fresh snapshot for the portfolio selected in the app,
        /// falling back to the account's first portfolio.
        static func fetchSnapshot(creds: Credentials, portfolioId: String?) async throws -> PortfolioSnapshot {
            var id = portfolioId
            if id == nil {
                let listData = try await get("/api/v3/data/portfolio", creds: creds)
                id = Parse.firstPortfolioId(listData)
            }
            guard let portfolioId = id else { throw Error.emptyPortfolio }

            let data = try await get("/api/v3/data/portfolio/\(portfolioId)", creds: creds)
            return try Parse.snapshot(data)
        }

        /// Fetches the portfolio's value history. The endpoint is undocumented,
        /// so this probes candidate paths and tolerates several response
        /// wrappers. The v3 guesses come first because that is the documented,
        /// HMAC-signed surface; chartAndCAGR is the path the web app really
        /// uses, which may or may not accept API-key auth.
        /// Throws `Error.badResponse` if no candidate yields decodable data.
        static func fetchHistory(creds: Credentials, portfolioId: String) async throws -> [HistoryPoint] {
            let candidates = [
                "/api/v3/data/portfolio/\(portfolioId)/history",
                "/api/v3/data/portfolio/\(portfolioId)/recap",
                "/api/v1/auth/portfolio/\(portfolioId)/chartAndCAGR",
            ]

            var unauthorizedCount = 0
            for path in candidates {
                do {
                    let data = try await get(path, creds: creds)
                    if let points = Parse.history(data) {
                        log.info("history: \(path, privacy: .public) answered with \(points.count) points")
                        return points
                    }
                    log.info("history: \(path, privacy: .public) 2xx but undecodable")
                } catch Error.unauthorized {
                    // A 401 on one path may only mean that path does not exist
                    // on this account, so keep probing; only a clean sweep is
                    // fatal.
                    unauthorizedCount += 1
                    log.info("history: \(path, privacy: .public) 401")
                } catch Error.rateLimited {
                    throw Error.rateLimited
                } catch {
                    log.info("history: \(path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    continue
                }
            }

            if unauthorizedCount == candidates.count { throw Error.unauthorized }
            throw Error.badResponse()
        }
    }

    // MARK: - MCP transport

    /// Kubera's MCP endpoint: stateless JSON-RPC over one POST with
    /// `Authorization: Basic <mcpToken>`. No session handshake is required, and
    /// a tool's payload comes back as text inside `result.content[0].text`.
    ///
    /// Every call goes through `call(tool:arguments:creds:)`, so adding a tool
    /// is a few lines rather than a new client.
    enum MCP {
        private static let endpoint = "https://api.kubera.com/api/v2/mcp"

        /// Tool names, none of which Kubera documents. `history` and
        /// `defaultPortfolio` are verified live; `portfolio` and `profile` are
        /// probed and logged.
        private enum Tool {
            static let history = "get_portfolio_history"
            static let portfolio = "get_portfolio"
            static let defaultPortfolio = "get_default_portfolio"
            static let profile = "get_profile"
        }

        /// A raw tools/call reply: the HTTP status plus the body, which may be
        /// plain JSON or SSE-framed. Transport failures throw instead.
        private struct Reply {
            let status: Int
            let body: Data
        }

        /// Calls one MCP tool and returns its text payload.
        ///
        /// Throws `Error.notConfigured` when no MCP token is saved (no request
        /// is made), the mapped HTTP error for a non-2xx reply, and
        /// `Error.badResponse` when the envelope carries an error or no text.
        static func call(tool: String, arguments: [String: Any] = [:], creds: Credentials) async throws -> String {
            guard let token = Parse.sanitizedToken(creds.mcpToken) else { throw Error.notConfigured }
            let reply = try await post(tool: tool, arguments: arguments, token: token)
            if let error = Error.from(httpStatus: reply.status) {
                log.info("mcp \(tool, privacy: .public): HTTP \(reply.status)")
                throw error
            }
            guard let text = Parse.toolText(in: reply.body) else {
                let detail = Parse.errorText(in: reply.body) ?? "no text content"
                log.info("mcp \(tool, privacy: .public): unusable payload (\(detail, privacy: .public))")
                throw Error.badResponse()
            }
            return text
        }

        /// Fetches the portfolio's value history via the `get_portfolio_history`
        /// tool. Requires the dedicated MCP token — the endpoint rejects the
        /// REST API key ("Kubera MCP: Invalid apiKey", verified live), so
        /// without a token this returns nil immediately.
        ///
        /// Every outcome is mirrored into `SharedStore.setHistoryStatus` so the
        /// Settings card can show what actually happened on the last attempt.
        static func fetchHistory(creds: Credentials, portfolioId: String) async -> [HistoryPoint]? {
            guard let token = Parse.sanitizedToken(creds.mcpToken) else {
                SharedStore.setHistoryStatus("No MCP token saved — growth builds from the on-device log instead.")
                return nil
            }

            let reply: Reply
            do {
                reply = try await post(
                    tool: Tool.history,
                    arguments: ["portfolioId": portfolioId],
                    token: token
                )
            } catch {
                log.info("mcp history: request failed")
                SharedStore.setHistoryStatus("History fetch failed: network error.")
                return nil
            }

            guard reply.status == 200 else {
                let body = String(data: reply.body.prefix(300), encoding: .utf8) ?? ""
                log.info("mcp history: HTTP \(reply.status): \(body, privacy: .public)")
                SharedStore.setHistoryStatus(
                    "History fetch failed (HTTP \(reply.status)): \(Parse.errorText(in: reply.body) ?? "unknown error")"
                )
                return nil
            }

            guard let points = Parse.historyPoints(inToolResponse: reply.body), !points.isEmpty else {
                let detail = Parse.errorText(in: reply.body)
                    ?? String(data: reply.body.prefix(120), encoding: .utf8).map { "body: \($0)" }
                    ?? "empty body"
                log.info("mcp history: 200 but no usable payload (\(detail, privacy: .public))")
                SharedStore.setHistoryStatus("History fetch failed: Kubera answered but the payload was unreadable (\(detail)).")
                return nil
            }

            log.info("mcp history: got \(points.count) points")
            SharedStore.setHistoryStatus("History: \(points.count) points from Kubera's API.")
            return points
        }

        /// Fetches the summary metrics and holdings table for a portfolio.
        ///
        /// The tool name is undocumented, so this asks `get_portfolio` for the
        /// selected portfolio first and falls back to `get_default_portfolio`,
        /// which takes no arguments; whichever answers is logged. Decoration —
        /// returns nil on any failure rather than throwing into the UI.
        static func fetchDetail(creds: Credentials, portfolioId: String?) async -> PortfolioDetail? {
            guard Parse.sanitizedToken(creds.mcpToken) != nil else { return nil }

            var attempts: [(tool: String, arguments: [String: Any])] = []
            if let portfolioId {
                attempts.append((Tool.portfolio, ["portfolioId": portfolioId]))
            }
            attempts.append((Tool.defaultPortfolio, [:]))

            for attempt in attempts {
                do {
                    let text = try await call(tool: attempt.tool, arguments: attempt.arguments, creds: creds)
                    guard let detail = Parse.detail(fromToolText: text) else {
                        log.info("mcp detail: \(attempt.tool, privacy: .public) answered but had no summary table")
                        continue
                    }
                    log.info("mcp detail: \(attempt.tool, privacy: .public) answered with \(detail.assets.count) assets")
                    return detail
                } catch {
                    log.info("mcp detail: \(attempt.tool, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    continue
                }
            }
            return nil
        }

        /// Fetches the signed-in user's name and email. Decoration — nil on any
        /// failure, including a payload that yielded neither field.
        static func fetchProfile(creds: Credentials) async -> KuberaProfile? {
            guard Parse.sanitizedToken(creds.mcpToken) != nil else { return nil }
            do {
                let profile = Parse.profile(fromToolText: try await call(tool: Tool.profile, creds: creds))
                log.info("mcp profile: \(Tool.profile, privacy: .public) answered, usable: \(profile != nil)")
                return profile
            } catch {
                log.info("mcp profile: failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }

        /// The one place a tools/call request is built and sent. Throws
        /// `Error.badResponse` for a transport failure; a non-2xx status comes
        /// back in the `Reply` so callers can report the server's own words.
        private static func post(tool: String, arguments: [String: Any], token: String) async throws -> Reply {
            var params: [String: Any] = ["name": tool]
            if !arguments.isEmpty { params["arguments"] = arguments }
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": params,
            ]

            guard let url = URL(string: endpoint),
                  let payload = try? JSONSerialization.data(withJSONObject: body) else {
                throw Error.badResponse()
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = payload

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else {
                throw Error.badResponse()
            }
            return Reply(status: http.statusCode, body: data)
        }
    }
}

// MARK: - Parsing

extension Kubera {
    /// Every decoder Kubera needs, JSON and markdown alike.
    ///
    /// Nothing here touches the network and nothing here traps: an unreadable
    /// cell becomes nil, a malformed row is skipped, and an absent metric stays
    /// absent rather than becoming zero (Kubera omits rows it has no value for,
    /// and zero would be a different claim).
    enum Parse {
        // MARK: - REST payloads

        /// The portfolio picker's list. An account with no portfolios decodes to
        /// an empty array.
        static func portfolios(_ data: Data) throws -> [PortfolioListItem] {
            let list = try JSONDecoder().decode(PortfolioListResponse.self, from: data)
            return (list.data ?? []).map {
                PortfolioListItem(
                    id: $0.id,
                    name: $0.name ?? $0.id,
                    currency: $0.currency ?? "USD"
                )
            }
        }

        /// The first portfolio's id, used when nothing is selected yet.
        static func firstPortfolioId(_ data: Data) -> String? {
            try? JSONDecoder().decode(PortfolioListResponse.self, from: data).data?.first?.id
        }

        /// Builds a snapshot from a portfolio detail response. Throws
        /// `Error.emptyPortfolio` when the envelope carries no portfolio.
        static func snapshot(_ data: Data) throws -> PortfolioSnapshot {
            let response = try JSONDecoder().decode(PortfolioDetailResponse.self, from: data)
            guard let portfolio = response.data else { throw Error.emptyPortfolio }

            let holdings = (portfolio.asset ?? [])
                .map { Holding(name: $0.name, value: $0.value?.amount ?? 0, sheet: $0.sheetName) }
                .sorted { $0.value > $1.value }
                .prefix(8)

            var allocation: [String: Double] = [:]
            for (key, value) in portfolio.allocationByAssetClass ?? [:] {
                if let value, value > 0 { allocation[key] = value }
            }

            return PortfolioSnapshot(
                portfolioId: portfolio.id,
                portfolioName: portfolio.name,
                currency: portfolio.ticker ?? portfolio.currency ?? "USD",
                netWorth: portfolio.netWorth ?? 0,
                assetTotal: portfolio.assetTotal ?? 0,
                debtTotal: portfolio.debtTotal ?? 0,
                costBasis: portfolio.costBasis ?? 0,
                unrealizedGain: portfolio.unrealizedGain ?? 0,
                topHoldings: Array(holdings),
                allocation: allocation,
                updatedAt: Date().timeIntervalSince1970
            )
        }

        /// Unwraps a history series from any of the shapes Kubera serves — REST
        /// wrappers, the chartAndCAGR nesting, or the MCP tool's bare payload —
        /// most specific first. nil when none of them yields points.
        static func history(_ data: Data) -> [HistoryPoint]? {
            let decoder = JSONDecoder()

            if let points = try? decoder.decode(HistoryGroupedEnvelope.self, from: data)
                .data?.portfolioDataPoints?.groupByDay?.netWorth, !points.isEmpty {
                return points
            }
            if let points = try? decoder.decode(HistoryPayloadEnvelope.self, from: data).data?.portfolioDataPoints,
               !points.isEmpty {
                return points
            }
            if let points = try? decoder.decode(HistoryPayload.self, from: data).portfolioDataPoints,
               !points.isEmpty {
                return points
            }
            if let points = try? decoder.decode(HistoryArrayEnvelope.self, from: data).data, !points.isEmpty {
                return points
            }
            if let points = try? decoder.decode([HistoryPoint].self, from: data), !points.isEmpty {
                return points
            }
            return nil
        }

        // MARK: - MCP envelope

        /// Kubera's docs show the header as "Basic AUTH_TOKEN"; people paste the
        /// whole thing. Strip the scheme so we don't send "Basic Basic …". nil
        /// when there is no usable token.
        static func sanitizedToken(_ raw: String?) -> String? {
            guard var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            // Trimming has already removed the trailing space, so the
            // scheme-only case has to be caught before the prefix test —
            // otherwise "Basic " survives as the token "Basic" and we send
            // an "Authorization: Basic Basic" header.
            if token.lowercased() == "basic" { return nil }
            if token.lowercased().hasPrefix("basic ") {
                token = String(token.dropFirst("basic ".count)).trimmingCharacters(in: .whitespaces)
            }
            return token.isEmpty ? nil : token
        }

        /// The full parsing path from a raw tools/call body to history points, so
        /// every server variant is testable without a network. Handles payloads
        /// in `content[].text` and in the spec's `structuredContent` field.
        static func historyPoints(inToolResponse data: Data) -> [HistoryPoint]? {
            guard let envelope = envelope(data), envelope.result?.isError != true else { return nil }
            if let text = envelope.text, let points = history(Data(text.utf8)), !points.isEmpty {
                return points
            }
            if let structured = envelope.result?.structuredContent,
               let data = try? JSONSerialization.data(withJSONObject: structured.value),
               let points = history(data), !points.isEmpty {
                return points
            }
            return nil
        }

        /// A tool's text payload, or nil when the envelope reports an error or
        /// carries no text content.
        static func toolText(in data: Data) -> String? {
            guard let envelope = envelope(data), envelope.result?.isError != true else { return nil }
            guard let text = envelope.text, !text.isEmpty else { return nil }
            return text
        }

        /// Digs the human-readable error out of the JSON-RPC envelope, e.g.
        /// "Kubera MCP: Invalid Token".
        static func errorText(in data: Data) -> String? {
            guard let text = envelope(data)?.text else { return nil }
            struct InnerError: Decodable { let error: String? }
            let inner = (try? JSONDecoder().decode(InnerError.self, from: Data(text.utf8)))?.error ?? text
            return String(inner.prefix(120))
        }

        /// Streamable-HTTP servers may answer a POST with plain JSON or with SSE
        /// framing ("event: message" / "data: {…}" lines). Try JSON first, then
        /// unwrap the data: lines and try again.
        static func envelope(_ data: Data) -> Envelope? {
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
    }
}

// MARK: - Response shapes

extension Kubera.Parse {
    // MARK: REST

    struct PortfolioListResponse: Decodable {
        let data: [PortfolioRef]?
    }

    struct PortfolioRef: Decodable {
        let id: String
        let name: String?
        let currency: String?
    }

    struct PortfolioDetailResponse: Decodable {
        let data: PortfolioData?
    }

    struct PortfolioData: Decodable {
        let id: String
        let name: String
        let ticker: String?
        let currency: String?
        let netWorth: Double?
        let assetTotal: Double?
        let debtTotal: Double?
        let costBasis: Double?
        let unrealizedGain: Double?
        let allocationByAssetClass: [String: Double?]?
        let asset: [AssetRow]?
    }

    struct AssetRow: Decodable {
        let name: String
        let value: AssetValue?
        let sheetName: String?
    }

    struct AssetValue: Decodable {
        let amount: Double?
    }

    // MARK: History wrappers

    struct HistoryPayload: Decodable {
        let portfolioDataPoints: [Kubera.HistoryPoint]?
    }

    struct HistoryPayloadEnvelope: Decodable {
        let data: HistoryPayload?
    }

    struct HistoryArrayEnvelope: Decodable {
        let data: [Kubera.HistoryPoint]?
    }

    /// The shape chartAndCAGR returns, where the points sit two levels deeper
    /// under portfolioDataPoints.groupByDay.netWorth.
    struct HistoryGroupedEnvelope: Decodable {
        let data: HistoryGroupedPayload?
    }

    struct HistoryGroupedPayload: Decodable {
        let portfolioDataPoints: HistoryGroups?
    }

    struct HistoryGroups: Decodable {
        let groupByDay: HistoryGroup?
    }

    struct HistoryGroup: Decodable {
        let netWorth: [Kubera.HistoryPoint]?
    }

    // MARK: JSON-RPC envelope

    struct Envelope: Decodable {
        let result: ToolResult?

        /// The first text content block, which is where every Kubera tool puts
        /// its payload.
        var text: String? {
            result?.content?.first { $0.type == "text" }?.text
        }
    }

    struct ToolResult: Decodable {
        let isError: Bool?
        let content: [Content]?
        let structuredContent: JSONValue?
    }

    struct Content: Decodable {
        let type: String?
        let text: String?
    }

    /// Decodes arbitrary JSON into Foundation objects so `structuredContent`
    /// (whose shape the server owns) can be re-serialized for parsing.
    struct JSONValue: Decodable {
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

// MARK: - Markdown parsing

/// Kubera's MCP tools answer in LLM-oriented markdown rather than JSON: an
/// `# Portfolio: …` heading, a `Currency: X | Generated: <ISO8601>` line, a
/// `## Summary` table of `| Metric | Value |` rows, then per-section tables
/// (`## Top Holdings`, `## Investable Assets`, `## Tax Estimate`, `## Assets`,
/// `## Debts`) whose column sets differ between sections and could change
/// without notice.
///
/// So every reader below degrades instead of failing: unknown columns are
/// ignored, unreadable cells become nil, malformed rows are skipped, and nothing
/// here can trap. `detail(fromToolText:)` gives up only when there is no summary
/// table at all.
extension Kubera.Parse {
    // MARK: - Entry points

    /// Parses a portfolio tool's payload. Returns nil when no `| Metric | Value |`
    /// summary table can be found, which is the one thing every response has.
    static func detail(fromToolText text: String) -> PortfolioDetail? {
        let document = markdown(fromToolText: text)
        guard let summary = summaryRows(in: document) else { return nil }

        return PortfolioDetail(
            currency: currency(in: document),
            netWorth: summaryValue("Net Worth", in: summary),
            assetTotal: summaryValue("Total Assets", in: summary),
            debtTotal: summaryValue("Total Debt", in: summary),
            cashOnHand: summaryValue("Cash On Hand", in: summary),
            estimatedTax: summaryValue("Total Estimated Tax", in: summary),
            investableTotal: investableTotal(in: document),
            costBasis: summaryValue("Cost Basis", in: summary),
            unrealizedGain: summaryValue("Unrealized Gain", in: summary),
            assets: assets(in: document),
            updatedAt: generatedAt(in: document) ?? Date().timeIntervalSince1970
        )
    }

    /// Parses a `get_profile` payload, which may be JSON or markdown. Returns nil
    /// unless a name or an email was actually found — a profile card with guessed
    /// contents is worse than no card.
    static func profile(fromToolText text: String) -> KuberaProfile? {
        if let profile = profileFromJSON(text) { return profile }
        return profile(name: labelledValue("Name", in: text), email: labelledValue("Email", in: text))
    }

    /// Kubera wraps the markdown in a JSON object (`{"defaultPortfolio":{"id",
    /// "name","currency","markdown"},"otherPortfolios":[…]}`) rather than
    /// returning it bare, so unwrap that when present and otherwise pass the
    /// text straight through.
    static func markdown(fromToolText text: String) -> String {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text
        }
        let containers: [[String: Any]] = [root]
            + ["defaultPortfolio", "portfolio"].compactMap { root[$0] as? [String: Any] }
        for container in containers {
            if let markdown = container["markdown"] as? String, !markdown.isEmpty {
                return markdown
            }
        }
        return text
    }

    // MARK: - Numbers

    /// Reads one markdown cell as a number. Handles thousands separators,
    /// currency symbols and trailing codes (`$1,234`, `1,234,567 USD`),
    /// accounting negatives (`(1,234)`), percent suffixes, bold markers, and both
    /// ASCII and typographic minus signs. Placeholders (`—`, `-`, `n/a`) and
    /// anything without digits read as nil rather than zero.
    static func number(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        text = text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }

        var digits = ""
        for character in text {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if character == "-" || character == "\u{2212}" {
                // A sign is only a sign ahead of the digits; afterwards it is a
                // range or a suffix, and the number has ended.
                if digits.isEmpty { negative = true } else { break }
            } else if character == "," || character == " " || character == "\u{00A0}" || character == "_" {
                continue
            } else if !digits.isEmpty {
                break
            }
        }
        guard !digits.isEmpty, let value = Double(digits), value.isFinite else { return nil }
        return negative ? -value : value
    }

    // MARK: - Summary table

    /// The `| Metric | Value |` rows, scoped to the `## Summary` section so the
    /// similarly shaped Concentration table cannot stand in for it.
    static func summaryRows(in markdown: String) -> [[String]]? {
        table(matching: ["Metric", "Value"], in: section("Summary", in: markdown) ?? markdown)?.rows
    }

    /// Reads one summary metric by label, ignoring case, spacing and bold. An
    /// absent row returns nil — Kubera omits Cash On Hand and Total Estimated Tax
    /// entirely when they are zero.
    static func summaryValue(_ metric: String, in rows: [[String]]) -> Double? {
        let wanted = normalized(metric)
        for row in rows where row.count >= 2 && normalized(row[0]) == wanted {
            return number(row[1])
        }
        return nil
    }

    // MARK: - Assets

    /// Holdings, taken from the ranked `## Top Holdings` table and falling back
    /// to `## Investable Assets` and then the full `## Assets` table, which is
    /// the only one that splits Sheet and Section into separate columns.
    static func assets(in markdown: String) -> [PortfolioDetail.Asset] {
        for name in ["Top Holdings", "Investable Assets", "Assets"] {
            guard let scope = section(name, in: markdown),
                  let table = table(matching: ["Name", "Value"], in: scope) else { continue }
            let assets = table.rows.compactMap { asset(fromRow: $0, in: table) }
            if !assets.isEmpty { return assets }
        }
        // No recognizable section headings: take the first table anywhere in the
        // document that looks like a holdings table.
        guard let table = table(matching: ["Name", "Value", "Asset Class"], in: markdown) else { return [] }
        return table.rows.compactMap { asset(fromRow: $0, in: table) }
    }

    /// One asset row. nil when the row has no readable name or value, which is
    /// how a malformed row is skipped.
    static func asset(fromRow row: [String], in table: Table) -> PortfolioDetail.Asset? {
        guard let name = cleaned(table.cell("Name", in: row)),
              let value = number(table.cell("Value", in: row)) else { return nil }

        let (sheet, section) = splitSheetSection(table.cell("Sheet > Section", in: row))
        return PortfolioDetail.Asset(
            name: name,
            value: value,
            assetClass: cleaned(table.cell("Asset Class", in: row)),
            ticker: cleaned(table.cell("Ticker", in: row)),
            sheet: sheet ?? cleaned(table.cell("Sheet", in: row)),
            section: section ?? cleaned(table.cell("Section", in: row))
        )
    }

    /// Splits Kubera's combined `Sheet > Section` cell. A missing side, a bare
    /// placeholder, or a missing cell yields nils.
    static func splitSheetSection(_ raw: String?) -> (sheet: String?, section: String?) {
        guard let raw = cleaned(raw) else { return (nil, nil) }
        guard let separator = raw.range(of: ">") else { return (raw, nil) }
        return (
            cleaned(String(raw[raw.startIndex ..< separator.lowerBound])),
            cleaned(String(raw[separator.upperBound...]))
        )
    }

    // MARK: - Header facts

    /// Reporting currency, from the `Currency: USD | Generated: …` header line.
    static func currency(in markdown: String) -> String? {
        guard let raw = labelledValue("Currency", in: markdown) else { return nil }
        return cleaned(raw.split(separator: " ").first.map(String.init) ?? raw)
    }

    /// The `Generated:` timestamp, as seconds since 1970.
    static func generatedAt(in markdown: String) -> Double? {
        guard let stamp = labelledValue("Generated", in: markdown) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: stamp) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: stamp)?.timeIntervalSince1970
    }

    /// Total investable value, which lives in prose under the Investable Assets
    /// heading (`Total Investable: 1,234,567 USD (65.2% of assets)`) rather than
    /// in the summary table.
    static func investableTotal(in markdown: String) -> Double? {
        let scope = section("Investable Assets", in: markdown) ?? markdown
        if let line = labelledValue("Total Investable", in: scope), let value = number(line) {
            return value
        }
        // Some payloads may carry it as a summary row instead.
        guard let rows = summaryRows(in: markdown) else { return nil }
        return summaryValue("Total Investable", in: rows) ?? summaryValue("Investable", in: rows)
    }

    /// Reads a `Label: value` line — also matching `**Label**: value`,
    /// `- Label: value`, one segment of a pipe-packed header line such as
    /// `Currency: USD | Generated: …`, and a `| Label | value |` table row.
    static func labelledValue(_ label: String, in text: String) -> String? {
        let wanted = normalized(label)
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                let cells = cells(in: line)
                if cells.count >= 2, normalized(cells[0]) == wanted, let value = cleaned(cells[1]) {
                    return value
                }
                continue
            }
            for rawSegment in line.split(separator: "|") {
                let segment = rawSegment.trimmingCharacters(in: .whitespaces)
                guard let colon = segment.firstIndex(of: ":") else { continue }
                let head = segment[segment.startIndex ..< colon]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*# "))
                guard normalized(head) == wanted else { continue }
                if let value = cleaned(String(segment[segment.index(after: colon)...])) { return value }
            }
        }
        return nil
    }

    // MARK: - Sections

    /// The text under a `## Name` heading, up to the next heading at the same or
    /// a higher level. Matching ignores case and the heading depth.
    static func section(_ name: String, in markdown: String) -> String? {
        let wanted = normalized(name)
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var start: Int?
        var depth = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            let title = normalized(String(trimmed.dropFirst(hashes)))

            if let start {
                guard hashes <= depth else { continue }
                return lines[start ..< index].joined(separator: "\n")
            }
            if title == wanted {
                start = index + 1
                depth = hashes
            }
        }
        guard let start, start <= lines.count else { return nil }
        return lines[start...].joined(separator: "\n")
    }

    // MARK: - Tables

    /// A markdown table's header and body, with column lookup by name.
    struct Table {
        let columns: [String]
        let rows: [[String]]

        /// Index of a column, preferring an exact name match and then a prefix
        /// match, so `Value` finds `Value (USD)` and `%` finds `% of Investable`
        /// without hard-coding the currency or the denominator.
        func index(of column: String) -> Int? {
            let wanted = Kubera.Parse.normalized(column)
            if let exact = columns.firstIndex(where: { Kubera.Parse.normalized($0) == wanted }) {
                return exact
            }
            return columns.firstIndex { Kubera.Parse.normalized($0).hasPrefix(wanted) }
        }

        /// One cell by column name, or nil when the column is absent or the row
        /// is short — Kubera's row and header widths do not always agree.
        func cell(_ column: String, in row: [String]) -> String? {
            guard let index = index(of: column), index < row.count else { return nil }
            return row[index]
        }
    }

    /// Finds the first table whose header carries all the named columns, and
    /// returns it with its body rows. Tolerates extra columns, a missing or
    /// unusual separator line, and short rows.
    static func table(matching columns: [String], in markdown: String) -> Table? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for (index, line) in lines.enumerated() where line.hasPrefix("|") {
            let header = cells(in: line)
            let candidate = Table(columns: header, rows: [])
            guard columns.allSatisfy({ candidate.index(of: $0) != nil }) else { continue }

            var rows: [[String]] = []
            for line in lines[(index + 1)...] {
                guard line.hasPrefix("|") else {
                    // A blank line inside a table is a formatting accident; a
                    // heading or a prose line ends it.
                    if line.isEmpty { continue } else { break }
                }
                if isSeparator(line) { continue }
                let row = cells(in: line)
                guard row.contains(where: { !$0.isEmpty }) else { continue }
                rows.append(row)
            }
            return Table(columns: header, rows: rows)
        }
        return nil
    }

    /// Splits a `| a | b |` row into trimmed cells. Empty cells are preserved so
    /// column positions stay aligned with the header.
    static func cells(in line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body = String(body.dropFirst()) }
        if body.hasSuffix("|") { body = String(body.dropLast()) }
        return body
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// True for a `| ---- | ---: |` alignment row, in any of its spellings.
    fileprivate static func isSeparator(_ line: String) -> Bool {
        let body = line.filter { !" |".contains($0) }
        return !body.isEmpty && body.allSatisfy { $0 == "-" || $0 == ":" }
    }

    // MARK: - Text helpers

    /// Case-, space- and emphasis-insensitive form used for every label and
    /// column comparison.
    fileprivate static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Strips markdown ornament from a cell and maps placeholders to nil, so an
    /// unset column never reaches the UI as a literal "—".
    fileprivate static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "↳", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders: Set<String> = ["", "-", "—", "–", "\u{2212}", "n/a", "na", "null", "nil", "none"]
        return placeholders.contains(text.lowercased()) ? nil : text
    }

    /// Decodes a JSON `get_profile` payload, accepting the field spellings
    /// Kubera might use and the common habit of nesting the object.
    fileprivate static func profileFromJSON(_ text: String) -> KuberaProfile? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let candidates: [[String: Any]] = [root]
            + ["profile", "user", "account", "me", "data"].compactMap { root[$0] as? [String: Any] }

        for object in candidates {
            let name = ["name", "fullName", "full_name", "displayName", "userName"]
                .lazy.compactMap { object[$0] as? String }.first
            let email = ["email", "emailAddress", "email_address"]
                .lazy.compactMap { object[$0] as? String }.first
            if let profile = profile(name: name, email: email) { return profile }
        }
        return nil
    }

    /// A profile, or nil when neither field survived cleaning.
    fileprivate static func profile(name: String?, email: String?) -> KuberaProfile? {
        let name = cleaned(name)
        let email = cleaned(email)
        guard name != nil || email != nil else { return nil }
        return KuberaProfile(name: name, email: email)
    }
}

// MARK: - Compatibility

/// The pre-SDK names, kept as thin forwards so existing call sites and tests
/// (widgets, `Trends`, `SharedStore`'s history log) did not all have to move at
/// once. New code should call `Kubera.REST` / `Kubera.MCP` directly.
enum KuberaAPI {
    typealias APIError = Kubera.Error
    typealias HistoryPoint = Kubera.HistoryPoint

    static func listPortfolios(creds: KuberaCredentials) async throws -> [PortfolioListItem] {
        try await Kubera.REST.listPortfolios(creds: creds)
    }

    static func fetchSnapshot(creds: KuberaCredentials, portfolioId: String?) async throws -> PortfolioSnapshot {
        try await Kubera.REST.fetchSnapshot(creds: creds, portfolioId: portfolioId)
    }

    static func fetchHistory(creds: KuberaCredentials, portfolioId: String) async throws -> [HistoryPoint] {
        try await Kubera.REST.fetchHistory(creds: creds, portfolioId: portfolioId)
    }

    static func parseHistory(_ data: Data) -> [HistoryPoint]? {
        Kubera.Parse.history(data)
    }
}

enum KuberaMCP {
    static func fetchHistory(creds: KuberaCredentials, portfolioId: String) async -> [KuberaAPI.HistoryPoint]? {
        await Kubera.MCP.fetchHistory(creds: creds, portfolioId: portfolioId)
    }

    static func parsePoints(fromToolResponse data: Data) -> [KuberaAPI.HistoryPoint]? {
        Kubera.Parse.historyPoints(inToolResponse: data)
    }
}
