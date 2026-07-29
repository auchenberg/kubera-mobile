import CryptoKit
import Foundation
import os

/// Minimal Kubera API client, used by the app and by widgets refreshing
/// themselves in the background. Requests are signed with HMAC-SHA256 over
/// `apiKey + unixTimestamp + METHOD + path`.
enum KuberaAPI {
    enum APIError: Error, LocalizedError {
        case badResponse(status: Int? = nil)
        case unauthorized
        case rateLimited
        case emptyPortfolio

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
            }
        }
    }

    private static let baseURL = "https://api.kubera.com"

    private static func request(_ path: String, creds: KuberaCredentials) async throws -> Data {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let payload = "\(creds.apiKey)\(timestamp)GET\(path)"
        let key = SymmetricKey(data: Data(creds.secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        guard let url = URL(string: baseURL + path) else { throw APIError.badResponse() }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(creds.apiKey, forHTTPHeaderField: "x-api-token")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.setValue(signature, forHTTPHeaderField: "x-signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse() }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode)
        }
        return data
    }

    // MARK: - Response models

    private struct PortfolioListResponse: Decodable {
        let data: [PortfolioRef]?
    }

    private struct PortfolioRef: Decodable {
        let id: String
        let name: String?
        let currency: String?
    }

    private struct PortfolioDetailResponse: Decodable {
        let data: PortfolioData?
    }

    private struct PortfolioData: Decodable {
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
        let asset: [Asset]?
    }

    private struct Asset: Decodable {
        let name: String
        let value: Value?
        let sheetName: String?
    }

    private struct Value: Decodable {
        let amount: Double?
    }

    /// One day of portfolio history. Every figure but the date is optional:
    /// the endpoint is undocumented and has been seen omitting fields. The
    /// extra `rv*` keys the web app's endpoint returns are ignored.
    struct HistoryPoint: Codable {
        let date: String // "yyyy-MM-dd"
        let value: Double? // net worth
        let assetTotal: Double?
        let debtTotal: Double?
        let investibleTotal: Double?
    }

    private struct HistoryPayload: Decodable {
        let portfolioDataPoints: [HistoryPoint]?
    }

    private struct HistoryPayloadEnvelope: Decodable {
        let data: HistoryPayload?
    }

    private struct HistoryArrayEnvelope: Decodable {
        let data: [HistoryPoint]?
    }

    /// The shape chartAndCAGR returns, where the points sit two levels deeper
    /// under portfolioDataPoints.groupByDay.netWorth.
    private struct HistoryGroupedEnvelope: Decodable {
        let data: HistoryGroupedPayload?
    }

    private struct HistoryGroupedPayload: Decodable {
        let portfolioDataPoints: HistoryGroups?
    }

    private struct HistoryGroups: Decodable {
        let groupByDay: HistoryGroup?
    }

    private struct HistoryGroup: Decodable {
        let netWorth: [HistoryPoint]?
    }

    // MARK: - Public API

    /// Lists the portfolios on the account, for the picker in settings.
    /// Returns an empty array when the account has none.
    static func listPortfolios(creds: KuberaCredentials) async throws -> [PortfolioListItem] {
        let data = try await request("/api/v3/data/portfolio", creds: creds)
        let list = try JSONDecoder().decode(PortfolioListResponse.self, from: data)
        return (list.data ?? []).map {
            PortfolioListItem(
                id: $0.id,
                name: $0.name ?? $0.id,
                currency: $0.currency ?? "USD"
            )
        }
    }

    /// Fetches a fresh snapshot for the portfolio selected in the app,
    /// falling back to the account's first portfolio.
    static func fetchSnapshot(creds: KuberaCredentials, portfolioId: String?) async throws -> PortfolioSnapshot {
        var id = portfolioId
        if id == nil {
            let listData = try await request("/api/v3/data/portfolio", creds: creds)
            let list = try JSONDecoder().decode(PortfolioListResponse.self, from: listData)
            id = list.data?.first?.id
        }
        guard let portfolioId = id else { throw APIError.emptyPortfolio }

        let data = try await request("/api/v3/data/portfolio/\(portfolioId)", creds: creds)
        let detail = try JSONDecoder().decode(PortfolioDetailResponse.self, from: data)
        guard let d = detail.data else { throw APIError.emptyPortfolio }

        let holdings = (d.asset ?? [])
            .map { Holding(name: $0.name, value: $0.value?.amount ?? 0, sheet: $0.sheetName) }
            .sorted { $0.value > $1.value }
            .prefix(8)

        var allocation: [String: Double] = [:]
        for (key, value) in d.allocationByAssetClass ?? [:] {
            if let value, value > 0 { allocation[key] = value }
        }

        return PortfolioSnapshot(
            portfolioId: d.id,
            portfolioName: d.name,
            currency: d.ticker ?? d.currency ?? "USD",
            netWorth: d.netWorth ?? 0,
            assetTotal: d.assetTotal ?? 0,
            debtTotal: d.debtTotal ?? 0,
            costBasis: d.costBasis ?? 0,
            unrealizedGain: d.unrealizedGain ?? 0,
            topHoldings: Array(holdings),
            allocation: allocation,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    /// Fetches the portfolio's value history. The endpoint is undocumented, so
    /// this probes candidate paths and tolerates several response wrappers.
    /// The v3 guesses come first because that is the documented, HMAC-signed
    /// surface; chartAndCAGR is the path the web app really uses, which may or
    /// may not accept API-key auth.
    /// Throws APIError.badResponse if no candidate yields decodable data.
    static func fetchHistory(creds: KuberaCredentials, portfolioId: String) async throws -> [HistoryPoint] {
        let candidates = [
            "/api/v3/data/portfolio/\(portfolioId)/history",
            "/api/v3/data/portfolio/\(portfolioId)/recap",
            "/api/v1/auth/portfolio/\(portfolioId)/chartAndCAGR",
        ]

        let log = Logger(subsystem: "com.auchenberg.kuberawidgets", category: "api")
        var unauthorizedCount = 0
        for path in candidates {
            do {
                let data = try await request(path, creds: creds)
                if let points = decodeHistory(data) {
                    log.info("history: \(path, privacy: .public) answered with \(points.count) points")
                    return points
                }
                log.info("history: \(path, privacy: .public) 2xx but undecodable")
            } catch APIError.unauthorized {
                // A 401 on one path may only mean that path does not exist on
                // this account, so keep probing; only a clean sweep is fatal.
                unauthorizedCount += 1
                log.info("history: \(path, privacy: .public) 401")
            } catch APIError.rateLimited {
                throw APIError.rateLimited
            } catch {
                log.info("history: \(path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                continue
            }
        }

        if unauthorizedCount == candidates.count { throw APIError.unauthorized }
        throw APIError.badResponse()
    }

    /// Parses a history payload in any of the shapes Kubera serves (REST
    /// wrappers, chartAndCAGR nesting, or the MCP tool's bare payload).
    static func parseHistory(_ data: Data) -> [HistoryPoint]? {
        decodeHistory(data)
    }

    /// Unwraps the history array from any of the shapes the endpoint has
    /// returned, most specific first. nil when none of them yields points.
    private static func decodeHistory(_ data: Data) -> [HistoryPoint]? {
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
}
