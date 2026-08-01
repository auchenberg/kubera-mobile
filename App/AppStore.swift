import Foundation
import Observation
import WidgetKit

/// Single source of truth for the app. Every mutation writes through to
/// `SharedStore` (Keychain + shared defaults) so the widget extension sees the
/// same state, and reloads the widget timelines afterwards.
@MainActor
@Observable
final class AppStore {
    /// A validation failure, carrying the field it belongs to so the connect
    /// screen can attach the message to the credential that caused it.
    struct CredentialError: LocalizedError {
        let feedback: CredentialFeedback

        var errorDescription: String? { feedback.text }
    }

    private(set) var credentials: KuberaCredentials?
    private(set) var portfolios: [PortfolioListItem] = []
    private(set) var selectedPortfolioId: String?
    private(set) var snapshot: PortfolioSnapshot?
    private(set) var settings: WidgetSettings
    private(set) var refreshing = false
    /// Per-surface health of the Kubera connection. REST (balances) and history
    /// (growth) fail independently, so Settings can say which one is broken.
    private(set) var connection: ConnectionStatus
    /// Observable mirrors of the widget data caches, so the in-app previews
    /// re-render the moment a refresh lands — they show exactly what the
    /// Home Screen widgets would show.
    private(set) var trends: PortfolioTrends?
    private(set) var comps: MarketComps?
    /// Facts only Kubera's MCP endpoint serves: the summary metrics behind the
    /// dashboard cards, the ranked holdings, and who is signed in. Decoration —
    /// nil whenever no MCP token is stored or the endpoint declined to answer.
    private(set) var detail: PortfolioDetail?
    private(set) var profile: KuberaProfile?

    /// The last request to show the assets tab. `MainTabView` watches it to
    /// select the tab and the assets screen watches it to pick a sheet, so a
    /// widget URL and a tap on the Overview travel the same road.
    ///
    /// Never cleared. Both watchers act on the *change*, not on the value being
    /// present, and the serial inside makes even a repeat of the same sheet a
    /// change — clearing it would only add a second write for them to react to.
    private(set) var assetsRequest: AssetsRequest?

    /// In-flight refresh, so the launch refresh and a pull-to-refresh don't
    /// both hit the API — the second caller awaits the first one's result.
    private var refreshTask: Task<Void, Error>?

    init() {
        #if DEBUG
        if AppStore.isDemoRun {
            credentials = DemoData.credentials
            portfolios = DemoData.portfolios
            selectedPortfolioId = DemoData.portfolios.first?.id
            snapshot = DemoData.snapshot
            // App Lock off: a demo run has nothing to protect, and a simulator
            // with no enrolled biometrics would open on a passcode sheet.
            var demoSettings = WidgetSettings()
            demoSettings.appLockEnabled = false
            settings = demoSettings
            trends = DemoData.trends
            comps = DemoData.comps
            detail = DemoData.detail
            profile = DemoData.profile
            connection = ConnectionStatus(
                rest: .connected(at: Date(timeIntervalSince1970: DemoData.snapshot.updatedAt)),
                history: .connected(points: DemoData.history.count)
            )
            return
        }
        #endif

        SharedStore.migrateLegacyCredentialsIfNeeded()
        let storedCredentials = SharedStore.credentials()
        let cachedSnapshot = SharedStore.cachedSnapshot()

        credentials = storedCredentials
        selectedPortfolioId = SharedStore.selectedPortfolioId()
        snapshot = cachedSnapshot
        settings = SharedStore.settings()
        trends = SharedStore.cachedTrends()
        comps = SharedStore.cachedMarketComps()
        detail = SharedStore.cachedDetail()
        profile = SharedStore.cachedProfile()

        // Seed the status from what is on disk, so Settings has something true
        // to show before the first refresh lands: a cached snapshot means REST
        // worked when it was written, and the history line comes from the
        // outcome KuberaMCP recorded on its last attempt.
        connection = ConnectionStatus(
            rest: cachedSnapshot.map { .connected(at: Date(timeIntervalSince1970: $0.updatedAt)) } ?? .unknown,
            history: ConnectionStatus.history(
                fromStatusLine: SharedStore.historyStatus(),
                hasToken: storedCredentials?.mcpToken != nil
            )
        )
    }

    #if DEBUG
    /// Renders the whole app against `DemoData` with no Kubera account and
    /// nothing written to the Keychain or the shared container. Two uses: taking
    /// the README screenshots, and letting someone who has cloned this repo
    /// without a Kubera subscription see what it does.
    ///
    /// Debug-only and launch-argument-gated, so it cannot be reached in a release
    /// build or by any in-app action:
    ///
    ///     xcrun simctl launch <device> com.kubera.mobile -KuberaDemoMode YES
    static var isDemoRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-KuberaDemoMode")
            || UserDefaults.standard.bool(forKey: "KuberaDemoMode")
    }
    #endif

    // MARK: - Session

    /// First-run connect. Validates and stores all three credentials; returns
    /// non-nil when the optional MCP token was rejected, which degrades growth
    /// history but is not a reason to refuse the connection.
    @discardableResult
    func signIn(apiKey: String, secret: String, mcpToken: String = "") async throws -> CredentialFeedback? {
        try await updateCredentials(
            apiKey: .set(apiKey),
            secret: .set(secret),
            mcpToken: CredentialInput.trimmed(mcpToken).isEmpty ? .cleared : .set(mcpToken)
        )
    }

    /// Replaces one or more credentials in place. Untouched fields keep their
    /// stored value, and **no cache is cleared** — the snapshot, trends, market
    /// comps, on-device history log and the selected portfolio all survive, so
    /// fixing a typo in a key does not cost months of recorded history.
    ///
    /// Throws `CredentialError` if the key and secret don't validate; the stored
    /// pair is left alone in that case. A rejected MCP token is still saved and
    /// reported through the return value, since the user typed it deliberately
    /// and the History status line explains what happened.
    @discardableResult
    func updateCredentials(
        apiKey: CredentialEdit = .unchanged,
        secret: CredentialEdit = .unchanged,
        mcpToken: CredentialEdit = .unchanged
    ) async throws -> CredentialFeedback? {
        guard let merged = KuberaCredentials.merged(
            into: credentials,
            apiKey: apiKey,
            secret: secret,
            mcpToken: mcpToken
        ) else {
            throw CredentialError(feedback: .missingRequired)
        }

        let isFirstConnect = credentials == nil

        // Validating before storing is what keeps a bad paste from replacing a
        // working key.
        let found: [PortfolioListItem]
        do {
            found = try await KuberaAPI.listPortfolios(creds: merged)
        } catch {
            connection.rest = ConnectionStatus.rest(from: error)
            throw CredentialError(feedback: .forRestError(error))
        }
        if isFirstConnect, found.isEmpty {
            throw CredentialError(feedback: .noPortfolios)
        }
        connection.rest = .connected(at: Date())

        credentials = merged
        portfolios = found
        SharedStore.saveCredentials(merged)

        // Only move the widget's portfolio if the stored one is gone — e.g. the
        // key now points at a different account.
        let selectionStillExists = selectedPortfolioId.map { id in found.contains { $0.id == id } } ?? false
        if !selectionStillExists, let first = found.first {
            selectedPortfolioId = first.id
            SharedStore.setSelectedPortfolioId(first.id)
        }

        if mcpToken != .unchanged {
            await validateHistory(creds: merged)
        }

        // Pull fresh balances under the new credentials. They are already
        // validated, so a failure here leaves the cached snapshot on screen
        // rather than failing the save.
        if let portfolioId = selectedPortfolioId {
            try? await loadSnapshot(creds: merged, portfolioId: portfolioId)
        }
        reloadWidgets()

        return CredentialFeedback.forHistory(connection.history)
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        credentials = nil
        portfolios = []
        selectedPortfolioId = nil
        snapshot = nil
        trends = nil
        comps = nil
        detail = nil
        profile = nil
        connection = ConnectionStatus()
        SharedStore.clearCredentials()
        SharedStore.setSelectedPortfolioId(nil)
        SharedStore.clearSnapshot()
        SharedStore.clearTrends()
        SharedStore.clearDetail()
        SharedStore.clearProfile()
        SharedStore.clearLocalHistory()
        SharedStore.clearHistoryStatus()
        reloadWidgets()
    }

    // MARK: - Navigation

    /// Ask for the assets tab, optionally on a named sheet.
    ///
    /// The single entry point: `kubera://assets`, the Overview's composition
    /// rows and its ASSETS card all call this, so there is one behaviour to
    /// reason about rather than one per caller. A nil sheet means "show me that
    /// screen" and leaves the selection it already had.
    func showAssets(sheetID: String? = nil) {
        assetsRequest = .next(after: assetsRequest, sheetID: sheetID)
    }

    // MARK: - Data

    /// The merged server + on-device history the chart, the trends and the
    /// widgets all read, so none of them can disagree about the curve.
    ///
    /// Goes through the store rather than being read from `SharedStore` at the
    /// call site so a demo run has a series too: it deliberately writes nothing
    /// to the shared container, which would otherwise leave the chart empty and
    /// claiming Kubera had served no history.
    var history: [KuberaAPI.HistoryPoint] {
        #if DEBUG
        if AppStore.isDemoRun { return DemoData.history }
        #endif
        return SharedStore.localHistory()
    }

    func refresh() async throws {
        #if DEBUG
        // A demo run holds credentials Kubera would reject, and letting the
        // launch refresh reach the network would replace the seeded state with
        // an auth failure the moment the app opened.
        if AppStore.isDemoRun { return }
        #endif
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    /// Re-checks both surfaces against the stored credentials without changing
    /// them, for the status header in Settings.
    func checkConnection() async {
        #if DEBUG
        if AppStore.isDemoRun { return }
        #endif
        guard let creds = credentials else {
            connection = ConnectionStatus()
            return
        }
        do {
            if let portfolioId = selectedPortfolioId {
                // Loading a snapshot also refreshes trends, which is what
                // updates the history line.
                try await loadSnapshot(creds: creds, portfolioId: portfolioId)
            } else {
                portfolios = try await KuberaAPI.listPortfolios(creds: creds)
                connection.rest = .connected(at: Date())
                await validateHistory(creds: creds)
            }
        } catch {
            connection.rest = ConnectionStatus.rest(from: error)
        }
    }

    func selectPortfolio(_ id: String) async {
        selectedPortfolioId = id
        SharedStore.setSelectedPortfolioId(id)
        guard let creds = credentials else {
            reloadWidgets()
            return
        }
        // A failed fetch leaves the previous snapshot on screen; the dashboard
        // surfaces errors through its own refresh path.
        try? await loadSnapshot(creds: creds, portfolioId: id)
    }

    /// Saves the Kubera MCP token (Settings → API → MCP Token) onto the stored
    /// credentials. Kept as a thin wrapper over `updateCredentials`.
    func saveMCPToken(_ token: String) async {
        let edit: CredentialEdit = CredentialInput.trimmed(token).isEmpty ? .cleared : .set(token)
        _ = try? await updateCredentials(mcpToken: edit)
    }

    func updateSettings(_ mutate: (inout WidgetSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        SharedStore.save(settings: next)
        reloadWidgets()
    }

    // MARK: - Internals

    private func performRefresh() async throws {
        guard let creds = credentials, let portfolioId = selectedPortfolioId else { return }
        refreshing = true
        defer { refreshing = false }

        do {
            if portfolios.isEmpty {
                portfolios = try await KuberaAPI.listPortfolios(creds: creds)
            }
            try await loadSnapshot(creds: creds, portfolioId: portfolioId)
        } catch {
            connection.rest = ConnectionStatus.rest(from: error)
            throw error
        }
    }

    private func loadSnapshot(creds: KuberaCredentials, portfolioId: String) async throws {
        let fetched = try await KuberaAPI.fetchSnapshot(creds: creds, portfolioId: portfolioId)
        snapshot = fetched
        connection.rest = .connected(at: Date(timeIntervalSince1970: fetched.updatedAt))
        SharedStore.cache(snapshot: fetched)
        reloadWidgets()
        await refreshTrends(creds: creds, snapshot: fetched)
    }

    /// Primes the trends and comps caches so a freshly added widget can render
    /// immediately instead of waiting for its own fetches, and mirrors them
    /// into observable state for the in-app previews. Optional decoration —
    /// failures are silent and keep the previous cached values.
    private func refreshTrends(creds: KuberaCredentials, snapshot: PortfolioSnapshot) async {
        let refreshed = await TrendsCalculator.refresh(creds: creds, snapshot: snapshot)
        comps = await MarketCompsFetcher.cachedOrFresh()
        connection.history = ConnectionStatus.history(
            fromStatusLine: SharedStore.historyStatus(),
            hasToken: creds.mcpToken != nil
        )
        await refreshDetail(creds: creds, portfolioId: snapshot.portfolioId)
        guard let refreshed else { return }
        trends = refreshed
        reloadWidgets()
    }

    /// Pulls the MCP-only summary metrics and the account profile. Both are
    /// decoration: a failure leaves the cached values in place and must never
    /// fail the refresh that called it.
    private func refreshDetail(creds: KuberaCredentials, portfolioId: String) async {
        if let fetched = await Kubera.MCP.fetchDetail(creds: creds, portfolioId: portfolioId) {
            detail = fetched
            SharedStore.cache(detail: fetched)
        }
        if let fetched = await Kubera.MCP.fetchProfile(creds: creds) {
            profile = fetched
            SharedStore.cache(profile: fetched)
        }
    }

    /// Validates the MCP token by actually asking Kubera for history — the only
    /// honest check, since a well-formed token can still be rejected.
    /// `Kubera.MCP` records every outcome in shared defaults; this reads that
    /// back as a typed status.
    private func validateHistory(creds: KuberaCredentials) async {
        guard creds.mcpToken != nil else {
            // Stale outcomes belong to the token that just went away.
            SharedStore.clearHistoryStatus()
            connection.history = .localLogOnly
            return
        }
        guard let portfolioId = selectedPortfolioId ?? portfolios.first?.id ?? snapshot?.portfolioId else {
            connection.history = .unknown
            return
        }
        _ = await KuberaMCP.fetchHistory(creds: creds, portfolioId: portfolioId)
        connection.history = ConnectionStatus.history(
            fromStatusLine: SharedStore.historyStatus(),
            hasToken: true
        )
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
