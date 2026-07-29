import Foundation

/// Health of the two independent Kubera surfaces the app talks to.
///
/// Balances come from the HMAC REST API (`KuberaAPI`); growth history comes
/// only from the MCP endpoint (`KuberaMCP`) and needs its own token. Either can
/// work while the other is broken, so the two are modelled and displayed
/// separately rather than as one "signed in" flag.
///
/// Everything here is pure: the derivation from a thrown `KuberaAPI.APIError`
/// and from the human status line `KuberaMCP` leaves in
/// `SharedStore.historyStatus()` is unit-tested, and no member touches the
/// network or the defaults suite.
struct ConnectionStatus: Codable, Equatable {
    /// The HMAC REST API — net worth, assets, debts, holdings, allocation.
    enum Rest: Codable, Equatable {
        case unknown
        case connected(at: Date)
        case authFailed
        case rateLimited
        case failed(String)
    }

    /// Kubera's MCP history API — 1 day, YTD and CAGR.
    ///
    /// `localLogOnly` is the no-token case and is *not* an error: growth still
    /// renders, estimated from the on-device log.
    enum History: Codable, Equatable {
        case unknown
        case connected(points: Int)
        case localLogOnly
        case failed(String)
    }

    var rest: Rest
    var history: History

    init(rest: Rest = .unknown, history: History = .unknown) {
        self.rest = rest
        self.history = history
    }

    // MARK: - Presentation

    /// Semantic colour role, so this model stays free of SwiftUI.
    enum Role: Equatable {
        case positive
        case negative
        case dim
    }

    /// One rendered status line: "History · connected · 182 points from Kubera".
    struct Line: Equatable {
        let surface: String
        let state: String
        let detail: String?
        let role: Role
    }

    func restLine(now: Date = Date()) -> Line {
        switch rest {
        case .unknown:
            return Line(surface: "REST", state: "not checked yet", detail: nil, role: .dim)
        case let .connected(at):
            return Line(
                surface: "REST",
                state: "connected",
                detail: "balances updated \(Self.relativeTime(from: at, to: now))",
                role: .positive
            )
        case .authFailed:
            return Line(
                surface: "REST",
                state: "authentication failed",
                detail: "Kubera rejected this key and secret.",
                role: .negative
            )
        case .rateLimited:
            return Line(
                surface: "REST",
                state: "rate limited",
                detail: "Try again in a minute.",
                role: .negative
            )
        case let .failed(reason):
            return Line(surface: "REST", state: "not connected", detail: reason, role: .negative)
        }
    }

    var historyLine: Line {
        switch history {
        case .unknown:
            return Line(surface: "History", state: "not checked yet", detail: nil, role: .dim)
        case let .connected(points):
            return Line(
                surface: "History",
                state: "connected",
                detail: "\(points) point\(points == 1 ? "" : "s") from Kubera",
                role: .positive
            )
        case .localLogOnly:
            return Line(
                surface: "History",
                state: "using on-device log",
                detail: "Add an MCP token for Kubera's own history.",
                role: .dim
            )
        case let .failed(reason):
            return Line(
                surface: "History",
                state: "not connected",
                detail: "\(reason) Growth falls back to the on-device log.",
                role: .negative
            )
        }
    }

    /// Overall verdict for the section header. A missing MCP token is a
    /// legitimate degraded mode, so it never reads as a problem.
    var headline: String {
        switch (rest, history) {
        case (.unknown, .unknown):
            return "Not checked yet"
        case (.authFailed, _), (.rateLimited, _), (.failed, _):
            return "Needs attention"
        case (_, .failed):
            return "Needs attention"
        case (.connected, _):
            return "Connected"
        case (.unknown, _):
            return "Not checked yet"
        }
    }

    var headlineRole: Role {
        switch headline {
        case "Connected": return .positive
        case "Needs attention": return .negative
        default: return .dim
        }
    }

    // MARK: - Derivation

    /// Maps a REST failure onto the status. `KuberaAPI.APIError` cases get
    /// their own states; anything else keeps its localized description.
    static func rest(from error: Error) -> Rest {
        switch error {
        case KuberaAPI.APIError.unauthorized:
            return .authFailed
        case KuberaAPI.APIError.rateLimited:
            return .rateLimited
        case let error as KuberaAPI.APIError:
            return .failed(error.errorDescription ?? "Could not reach Kubera.")
        case is URLError:
            return .failed("Could not reach Kubera. Check your connection.")
        default:
            return .failed((error as? LocalizedError)?.errorDescription ?? "Could not reach Kubera.")
        }
    }

    /// Reads the human status line `KuberaMCP` writes after every history
    /// attempt. `hasToken` wins over a stale line: with no token stored the
    /// only truthful answer is the on-device log.
    ///
    /// The strings recognised here are exactly the ones
    /// `KuberaMCP.setHistoryStatus` emits — keep them in sync with that file.
    static func history(fromStatusLine line: String?, hasToken: Bool) -> History {
        guard hasToken else { return .localLogOnly }
        guard let line, !line.isEmpty else { return .unknown }

        if line.hasPrefix(pointsPrefix) {
            let rest = line.dropFirst(pointsPrefix.count)
            let digits = rest.prefix { $0.isNumber }
            if let count = Int(digits) { return .connected(points: count) }
            return .unknown
        }
        if line.hasPrefix("No MCP token saved") {
            return .localLogOnly
        }
        if line.hasPrefix("History fetch failed") {
            return .failed(failureReason(in: line))
        }
        return .unknown
    }

    private static let pointsPrefix = "History: "

    /// Turns one of `KuberaMCP`'s failure lines into copy aimed at the user.
    /// Falls back to the server's own text when nothing matches, because an
    /// unmapped Kubera error is still more useful than "something went wrong".
    private static func failureReason(in line: String) -> String {
        if line.contains("network error") {
            return "Could not reach Kubera."
        }
        if line.contains("payload was unreadable") {
            return "Kubera answered but the history payload was unreadable."
        }
        if let mapped = mcpErrorCopy(in: line) {
            return mapped
        }
        // "History fetch failed (HTTP 500): <server text>" — keep the text.
        if let colon = line.range(of: "): ") {
            return String(line[colon.upperBound...])
        }
        return "Kubera could not serve history."
    }

    /// The three MCP rejections seen live, mapped to copy that says what to do.
    static func mcpErrorCopy(in text: String) -> String? {
        if text.contains("Invalid apiKey") {
            return "That looks like your API key, not an MCP token."
        }
        if text.contains("Invalid Token") {
            return "Kubera rejected this MCP token."
        }
        if text.localizedCaseInsensitiveContains("missing authorization header") {
            return "The token field came through empty."
        }
        return nil
    }

    // MARK: - Relative time

    /// Short, deterministic "4 min ago". `RelativeDateTimeFormatter` is
    /// locale-dependent and untestable, and these lines are dense enough that
    /// its verbosity hurts.
    static func relativeTime(from date: Date, to now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<0: return "just now"
        case 0 ..< 60: return "just now"
        case 60 ..< 3600: return "\(seconds / 60) min ago"
        case 3600 ..< 86_400: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86_400) d ago"
        }
    }
}

/// Masked display of a stored credential. Settings shows enough of the API key
/// to tell two keys apart and nothing at all of the secrets.
enum CredentialMask {
    /// `kbra_pk_EXAMPLE_0001` → `kbra••••0001`. Short values mask entirely.
    static func key(_ value: String) -> String {
        guard value.count > 8 else { return "••••" }
        return "\(value.prefix(4))••••\(value.suffix(4))"
    }

    /// Secrets and tokens never show any of their characters, only a length band.
    static func secret(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Not set" }
        return String(repeating: "•", count: min(max(value.count, 8), 16))
    }
}

/// Cleanup applied the moment a credential is typed or pasted, so the user sees
/// the value that will actually be stored.
enum CredentialInput {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kubera's docs show the MCP header as `Basic AUTH_TOKEN` and people paste
    /// the whole thing. Mirrors `KuberaMCP`'s own sanitizer, applied at entry.
    static func sanitizedToken(_ value: String) -> String {
        var token = trimmed(value)
        if token.lowercased().hasPrefix("basic ") {
            token = String(token.dropFirst("basic ".count)).trimmingCharacters(in: .whitespaces)
        }
        return token
    }
}

/// What the connect screen wants done with one credential. A field the user
/// never typed into keeps its stored value — the screen shows masked
/// placeholders rather than real values, so "left empty" cannot mean "clear".
enum CredentialEdit: Equatable {
    case unchanged
    case set(String)
    /// Only reachable for the MCP token.
    case cleared
}

extension KuberaCredentials {
    /// Folds a set of edits into the stored credentials, or builds them from
    /// scratch when nothing is stored yet.
    ///
    /// Returns nil when the result would not be usable — the key and the secret
    /// are both required and neither can be cleared — so the caller can report
    /// that instead of writing a broken item to the Keychain.
    static func merged(
        into current: KuberaCredentials?,
        apiKey: CredentialEdit,
        secret: CredentialEdit,
        mcpToken: CredentialEdit
    ) -> KuberaCredentials? {
        guard let mergedKey = required(apiKey, stored: current?.apiKey),
              let mergedSecret = required(secret, stored: current?.secret) else { return nil }

        let token: String?
        switch mcpToken {
        case .unchanged:
            token = current?.mcpToken
        case .cleared:
            token = nil
        case let .set(value):
            let sanitized = CredentialInput.sanitizedToken(value)
            token = sanitized.isEmpty ? nil : sanitized
        }

        return KuberaCredentials(apiKey: mergedKey, secret: mergedSecret, mcpToken: token)
    }

    private static func required(_ edit: CredentialEdit, stored: String?) -> String? {
        switch edit {
        case .unchanged:
            return stored.flatMap { $0.isEmpty ? nil : $0 }
        case .cleared:
            return nil
        case let .set(value):
            let trimmed = CredentialInput.trimmed(value)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

/// Which field an error belongs under, plus the copy to show there. Validation
/// failures attach to the credential that failed instead of pooling in one
/// message under the button.
struct CredentialFeedback: Equatable {
    enum Field: Equatable {
        case keyAndSecret
        case mcpToken
        /// Not a single credential's fault — shown above the primary action.
        case banner
    }

    let field: Field
    let text: String

    /// Copy for a REST (key + secret) validation failure.
    static func forRestError(_ error: Error) -> CredentialFeedback {
        switch error {
        case KuberaAPI.APIError.unauthorized:
            return CredentialFeedback(
                field: .keyAndSecret,
                text: """
                Kubera rejected this key and secret. Check both — the secret is only shown \
                once, when you create the key.
                """
            )
        case KuberaAPI.APIError.rateLimited:
            return CredentialFeedback(
                field: .banner,
                text: "Kubera's rate limit was hit. Try again in a minute."
            )
        case is URLError:
            return CredentialFeedback(
                field: .banner,
                text: "Could not reach Kubera. Check your connection."
            )
        default:
            return CredentialFeedback(
                field: .banner,
                text: (error as? LocalizedError)?.errorDescription ?? "Could not reach Kubera."
            )
        }
    }

    /// The key works, but there is nothing on the account to show.
    static let noPortfolios = CredentialFeedback(
        field: .banner,
        text: "This key works, but the account has no portfolios."
    )

    /// The merge left a required field empty.
    static let missingRequired = CredentialFeedback(
        field: .keyAndSecret,
        text: "Both the API key and the API secret are needed."
    )

    /// Copy for an MCP token validation failure, derived from the same status
    /// line the History status uses. nil when the token is fine or absent.
    static func forHistory(_ history: ConnectionStatus.History) -> CredentialFeedback? {
        switch history {
        case .connected, .localLogOnly, .unknown:
            return nil
        case let .failed(reason):
            return CredentialFeedback(field: .mcpToken, text: reason)
        }
    }
}
