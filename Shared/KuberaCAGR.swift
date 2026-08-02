import Foundation
import os

// MARK: - Model

/// Kubera's own compound annual growth rate for a portfolio, as served by the
/// `get_portfolio_cagr` MCP tool — the figure Kubera's dashboard prints, which
/// is measured over the portfolio's whole recorded life rather than over the
/// slice of history this device happens to hold.
///
/// Both figures are optional, and a payload that yields neither is discarded
/// rather than cached: the growth block falls back to the rate it computes
/// itself, and an empty record would only make a later "did the tool answer?"
/// question unanswerable.
struct PortfolioCAGR: Codable, Equatable {
    /// Percent per year, e.g. 12.4 — never a fraction. `Kubera.Parse` decides
    /// which spelling the payload used and normalizes before this is built, so
    /// nothing downstream has to know.
    let netWorth: Double?
    /// The same rate for investable assets, when the payload separates them.
    let investable: Double?
    let updatedAt: Double

    var isEmpty: Bool { netWorth == nil && investable == nil }
}

/// What the last `get_portfolio_cagr` probe learned, so the next refresh does
/// not pay for the same discovery again.
///
/// Kept because this tool is asked three different ways: `fetchDetail` re-probes
/// its two candidates on every refresh, which is affordable at two calls but not
/// at three — and unlike detail, whose first candidate is verified, the likely
/// steady state here is *all three failing*, which without a memory would cost
/// three wasted calls on every single refresh forever.
///
/// Persisted rather than held in memory because the app and the widget extension
/// are separate short-lived processes; an in-memory memo would be relearned on
/// every launch, which is most of the cost it exists to avoid.
struct KuberaCAGRProbe: Codable, Equatable {
    /// The argument key that answered, or `""` for the no-argument call — a real
    /// answer that has to be tellable from "nothing is remembered", which is nil.
    let answered: String?
    /// When a whole sweep came back with nothing, in unix seconds. Asking again
    /// straight away would only repeat it, so the fetch stands down until this
    /// has aged past `Kubera.MCP.cagrProbeRetry`.
    ///
    /// A transient outage lands here too, and is allowed to: the only cost of
    /// standing down is that the cached rate goes a few hours without being
    /// re-checked, while the alternative is telling apart "Kubera is down" from
    /// "this tool does not exist" on evidence that does not distinguish them.
    let failedAt: Double?
}

// MARK: - Transport

/// `get_portfolio_cagr` lives in its own file rather than in `Kubera.swift`
/// because it is the one tool whose response shape Kubera does not publish
/// anywhere: the help centre documents it as "A specific portfolio's CAGR by
/// ID" and stops. Everything below is written against a shape *inferred* from
/// the tools that are verified, is tolerant of being wrong, and refuses rather
/// than guesses whenever the payload is ambiguous — see
/// `cagrPercent(_:statedAsPercentage:)`, which is where the single risky
/// assumption lives.
extension Kubera.MCP {
    /// Undocumented, like every other Kubera tool name. Unverified: nothing in
    /// this app has ever called it.
    private static let cagrTool = "get_portfolio_cagr"

    private static let cagrLog = Logger(subsystem: "com.kubera.mobile", category: "api")

    /// How long a sweep that found nothing stands the fetch down for. Long
    /// enough that a tool name Kubera never ships costs four calls a day rather
    /// than three per refresh, short enough that the day Kubera does ship it,
    /// the figure appears without anyone reinstalling anything.
    static let cagrProbeRetry: TimeInterval = 6 * 60 * 60

    /// The argument spellings, in the order they are worth trying.
    ///
    /// All three are unverified. `portfolioId` is the spelling
    /// `get_portfolio_history` and `get_portfolio` both accept, so it leads;
    /// then the bare `id`; then no arguments at all, in case the tool defaults
    /// to the account's portfolio the way `get_default_portfolio` does.
    ///
    /// The key doubles as the memo's identifier, so reordering this list cannot
    /// invalidate what a device already learned.
    static func cagrAttempts(portfolioId: String?) -> [(key: String, arguments: [String: Any])] {
        var attempts: [(key: String, arguments: [String: Any])] = []
        if let portfolioId {
            attempts.append((key: "portfolioId", arguments: ["portfolioId": portfolioId]))
            attempts.append((key: "id", arguments: ["id": portfolioId]))
        }
        attempts.append((key: "", arguments: [:]))
        return attempts
    }

    /// What to ask, given what the last probe learned. Pure, so the policy that
    /// decides how many network calls a refresh costs is unit-testable without
    /// one.
    ///
    /// - A remembered spelling is the only one tried: the steady state is one
    ///   call per refresh, the same as any other tool.
    /// - A sweep that recently found nothing suppresses the fetch entirely.
    /// - Otherwise every spelling is tried, which happens once per device.
    static func cagrProbeOrder(
        after probe: KuberaCAGRProbe?,
        keys: [String],
        now: Date,
        retry: TimeInterval = cagrProbeRetry
    ) -> [String] {
        if let answered = probe?.answered, keys.contains(answered) { return [answered] }
        if let failedAt = probe?.failedAt, now.timeIntervalSince1970 - failedAt < retry { return [] }
        return keys
    }

    /// Fetches Kubera's CAGR for a portfolio.
    ///
    /// Decoration, like `fetchDetail`: nil on any failure, so the caller keeps
    /// whatever it had and the screen keeps computing its own rate.
    static func fetchCAGR(
        creds: Kubera.Credentials,
        portfolioId: String?,
        now: Date = Date()
    ) async -> PortfolioCAGR? {
        guard Kubera.Parse.sanitizedToken(creds.mcpToken) != nil else { return nil }

        let attempts = cagrAttempts(portfolioId: portfolioId)
        let probe = SharedStore.cagrProbe()
        let order = cagrProbeOrder(after: probe, keys: attempts.map(\.key), now: now)
        guard !order.isEmpty else {
            cagrLog.info("mcp cagr: standing down, the last sweep found nothing")
            return nil
        }

        if let cagr = await cagrSweep(order, in: attempts, creds: creds, now: now) { return cagr }

        // The remembered spelling stopped answering: forget it and try the ones
        // it displaced before giving up, so a change at Kubera's end costs one
        // refresh rather than the figure.
        if let answered = probe?.answered, order == [answered] {
            let rest = attempts.map(\.key).filter { $0 != answered }
            if let cagr = await cagrSweep(rest, in: attempts, creds: creds, now: now) { return cagr }
        }

        SharedStore.save(cagrProbe: KuberaCAGRProbe(answered: nil, failedAt: now.timeIntervalSince1970))
        return nil
    }

    /// Calls the tool once per key until one answers with a readable rate, and
    /// remembers the key that did.
    private static func cagrSweep(
        _ order: [String],
        in attempts: [(key: String, arguments: [String: Any])],
        creds: Kubera.Credentials,
        now: Date
    ) async -> PortfolioCAGR? {
        for key in order {
            guard let attempt = attempts.first(where: { $0.key == key }) else { continue }
            let shape = key.isEmpty ? "none" : key
            do {
                let text = try await call(tool: cagrTool, arguments: attempt.arguments, creds: creds)
                guard let cagr = Kubera.Parse.cagr(fromToolText: text, now: now), !cagr.isEmpty else {
                    // The payload itself is never logged: this tool answers
                    // about someone's money, and a device log is not the place
                    // for it. Its size and whether it was JSON are enough to
                    // tell "wrong shape" from "wrong tool name" while the live
                    // shape is still unknown.
                    let looksStructured = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                    cagrLog.info(
                        """
                        mcp cagr: args(\(shape, privacy: .public)) answered but carried no readable rate \
                        (\(text.count) chars, json: \(looksStructured))
                        """
                    )
                    continue
                }
                cagrLog.info("mcp cagr: args(\(shape, privacy: .public)) answered, investable: \(cagr.investable != nil)")
                SharedStore.save(cagrProbe: KuberaCAGRProbe(answered: key, failedAt: nil))
                return cagr
            } catch {
                cagrLog.info(
                    "mcp cagr: args(\(shape, privacy: .public)) failed: \(String(describing: error), privacy: .public)"
                )
                continue
            }
        }
        return nil
    }
}

// MARK: - Parsing

extension Kubera.Parse {
    /// Values outside this band are refused. A CAGR cannot fall below −100%
    /// (that is everything gone), and a four-figure one is a number that came
    /// out of the wrong column — an amount, a total, a basis point count.
    /// Refusing costs nothing, because the computed rate is waiting behind it.
    static let cagrPlausiblePercent: ClosedRange<Double> = -100 ... 1000

    /// Reads a `get_portfolio_cagr` payload. Returns nil unless a rate was
    /// actually found, which is what makes the fallback seamless: a shape that
    /// changed under us, a tool that answered about something else, or a value
    /// this cannot interpret all arrive at the caller as "no figure" rather than
    /// as a wrong one.
    ///
    /// Structured payloads are read first and markdown second, because the tools
    /// that are verified answer in markdown but the MCP spec's
    /// `structuredContent` is where a numeric answer would land if Kubera ever
    /// serves one.
    static func cagr(fromToolText text: String, now: Date = Date()) -> PortfolioCAGR? {
        var netWorth: Double?
        var investable: Double?

        if let fromJSON = cagrFromJSON(text) {
            netWorth = fromJSON.netWorth
            investable = fromJSON.investable
        }

        let document = markdown(fromToolText: text)
        if netWorth == nil || investable == nil {
            let fromMarkdown = cagrFromMarkdown(document)
            netWorth = netWorth ?? fromMarkdown.netWorth
            investable = investable ?? fromMarkdown.investable
        }

        guard netWorth != nil || investable != nil else { return nil }
        return PortfolioCAGR(
            netWorth: netWorth,
            investable: investable,
            updatedAt: generatedAt(in: document) ?? now.timeIntervalSince1970
        )
    }

    // MARK: - Percent or fraction

    /// The one genuinely unverified decision in this file: whether Kubera states
    /// a CAGR as a percentage (12.4) or as a fraction (0.124).
    ///
    /// - A `%` sign, or a key named for percent, settles it: percentage.
    /// - A bare magnitude of 1 or more is a percentage. Read as a fraction it
    ///   would claim a 100%-a-year portfolio, and reading a genuine fraction of
    ///   1.24 as 1.24% only understates a rate nobody has.
    /// - A bare magnitude below 1 is **ambiguous and refused**. 0.4 is either a
    ///   0.4% year or a 40% one, and printing 40% for a flat portfolio is the
    ///   kind of wrong number this integration exists not to produce. Falling
    ///   back to the computed rate costs the reader nothing.
    ///
    /// Once the live shape is known, this collapses to whichever branch is real.
    static func cagrPercent(_ value: Double, statedAsPercentage: Bool) -> Double? {
        guard value.isFinite else { return nil }
        guard statedAsPercentage || abs(value) >= 1 || value == 0 else { return nil }
        return cagrPlausiblePercent.contains(value) ? value : nil
    }

    /// One cell, header line or JSON scalar read as a rate. Strings carry their
    /// own `%` evidence; a raw number has only its magnitude.
    fileprivate static func cagrPercent(fromValue value: Any?, statedAsPercentage: Bool = false) -> Double? {
        if let text = value as? String {
            guard let parsed = number(text) else { return nil }
            return cagrPercent(parsed, statedAsPercentage: statedAsPercentage || text.contains("%"))
        }
        if let scalar = value as? NSNumber {
            return cagrPercent(scalar.doubleValue, statedAsPercentage: statedAsPercentage)
        }
        return nil
    }

    // MARK: - JSON payloads

    /// Reads a structured payload by key name rather than by a fixed shape:
    /// anything whose key mentions CAGR (or an annualized return) is a
    /// candidate, and a key that also mentions investable belongs to the other
    /// slot. Nested objects are walked two levels deep, which covers the
    /// `{"data": {…}}` and `{"cagr": {…}}` wrappers Kubera uses elsewhere.
    fileprivate static func cagrFromJSON(_ text: String) -> (netWorth: Double?, investable: Double?)? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var netWorth: Double?
        var investable: Double?

        for object in cagrObjects(in: root) {
            // Sorted so a payload carrying several spellings resolves the same
            // way every time rather than by dictionary order.
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                let name = key.lowercased()
                guard name.contains("cagr") || name.contains("annualized") else { continue }
                let statedAsPercentage = name.contains("percent") || name.contains("pct")

                // `{"cagr": {"netWorth": …, "investable": …}}`: the rate is
                // named by the parent and the metric by the child.
                if let nested = value as? [String: Any] {
                    let whole = nested.first { ["networth", "net_worth", "portfolio", "total", "value"].contains($0.key.lowercased()) }
                    let liquid = nested.first { $0.key.lowercased().contains("investable") }
                    netWorth = netWorth ?? cagrPercent(fromValue: whole?.value, statedAsPercentage: statedAsPercentage)
                    investable = investable ?? cagrPercent(fromValue: liquid?.value, statedAsPercentage: statedAsPercentage)
                    continue
                }

                guard let percent = cagrPercent(fromValue: value, statedAsPercentage: statedAsPercentage) else {
                    continue
                }
                if name.contains("investable") {
                    investable = investable ?? percent
                } else {
                    netWorth = netWorth ?? percent
                }
            }
        }

        guard netWorth != nil || investable != nil else { return nil }
        return (netWorth: netWorth, investable: investable)
    }

    /// The object and its nested objects, outermost first so a rate stated at
    /// the top level wins over one buried in a sub-object.
    fileprivate static func cagrObjects(in root: [String: Any], depth: Int = 2) -> [[String: Any]] {
        var found: [[String: Any]] = [root]
        guard depth > 0 else { return found }
        for value in root.values {
            guard let nested = value as? [String: Any] else { continue }
            found += cagrObjects(in: nested, depth: depth - 1)
        }
        return found
    }

    // MARK: - Markdown payloads

    /// Reads the shapes an LLM-oriented CAGR payload plausibly takes, most
    /// specific first: a table with a CAGR column, a labelled line or summary
    /// row, and finally the first percentage on any line that mentions CAGR at
    /// all — which is what catches a one-sentence answer.
    fileprivate static func cagrFromMarkdown(_ document: String) -> (netWorth: Double?, investable: Double?) {
        let table = cagrTable(in: document)

        let netWorth = table.flatMap { cagrRow(in: $0, labelled: cagrNetWorthLabels) }
            ?? ["Net Worth CAGR", "Portfolio CAGR", "CAGR", "Annualized Return", "Annualized Growth"]
            .lazy.compactMap { cagrLabelledPercent($0, in: document) }.first
            ?? cagrPercentNearMention(in: document)
        let investable = table.flatMap { cagrRow(in: $0, labelled: cagrInvestableLabels) }
            ?? ["Investable CAGR", "Investable Assets CAGR", "Investable Assets"]
            .lazy.compactMap { cagrLabelledPercent($0, in: document) }.first

        return (netWorth: netWorth, investable: investable)
    }

    /// Row labels that mean the portfolio as a whole. The period spellings are
    /// here because a table of CAGR by horizon is as likely a shape as one of
    /// CAGR by metric, and the figure Kubera's dashboard prints is the
    /// since-inception one.
    private static let cagrNetWorthLabels = [
        "net worth", "networth", "portfolio", "total", "overall",
        "all", "all time", "since inception", "inception", "lifetime",
    ]

    private static let cagrInvestableLabels = ["investable", "investable assets"]

    /// The first table carrying a column named for a rate. `Table.index(of:)`
    /// matches on prefix, so `CAGR (%)` and `CAGR %` are found too.
    fileprivate static func cagrTable(in document: String) -> Table? {
        table(matching: ["CAGR"], in: document)
    }

    /// A rate from the first row whose leading cell names one of the metrics,
    /// or from the only data row when a single-row table names nothing this
    /// recognizes — a one-row answer has no other row it could mean.
    fileprivate static func cagrRow(in table: Table, labelled labels: [String]) -> Double? {
        for row in table.rows {
            guard let label = cagrLabel(row.first),
                  labels.contains(where: { label.hasPrefix($0 + " ") }) else { continue }
            if let percent = cagrPercent(fromValue: table.cell("CAGR", in: row)) { return percent }
        }
        guard table.rows.count == 1, labels == cagrNetWorthLabels else { return nil }
        return cagrPercent(fromValue: table.cell("CAGR", in: table.rows[0]))
    }

    /// A row's leading cell, reduced for comparison and given a trailing space.
    /// Local rather than the SDK's `normalized`, which is fileprivate to
    /// `Kubera.swift`. The space is what makes the prefix test safe: a label is
    /// matched at a word boundary, so "Net Worth (USD)" still reads as net
    /// worth while "Allocation" does not read as the "All" period row.
    fileprivate static func cagrLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text + " "
    }

    /// A `Label: 12.4%` line, `**Label**: …`, or a `| Label | 12.4% |` row —
    /// `labelledValue` already reads all three.
    fileprivate static func cagrLabelledPercent(_ label: String, in document: String) -> Double? {
        cagrPercent(fromValue: labelledValue(label, in: document))
    }

    /// Last resort for prose: the first percentage on a line that says CAGR.
    /// Only a `%`-signed figure counts, so this can never resurrect the
    /// ambiguity `cagrPercent(_:statedAsPercentage:)` refuses.
    fileprivate static func cagrPercentNearMention(in document: String) -> Double? {
        for line in document.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard text.lowercased().contains("cagr"), let percent = percentBeforeSign(in: text) else { continue }
            return cagrPercent(percent, statedAsPercentage: true)
        }
        return nil
    }

    /// The number immediately left of the first `%`, read backwards so
    /// "grew at 12.4% a year" yields 12.4 rather than the year.
    fileprivate static func percentBeforeSign(in text: String) -> Double? {
        guard let sign = text.firstIndex(of: "%") else { return nil }
        var digits = ""
        for character in text[text.startIndex ..< sign].reversed() {
            if character.isNumber || character == "." || character == "," {
                digits.insert(character, at: digits.startIndex)
            } else if character == "-" || character == "\u{2212}" {
                guard !digits.isEmpty else { return nil }
                digits.insert("-", at: digits.startIndex)
                break
            } else if digits.isEmpty {
                // Whitespace or ornament between the figure and its sign.
                continue
            } else {
                break
            }
        }
        return number(digits)
    }
}
