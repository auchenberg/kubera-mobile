import Foundation
import Observation
import WidgetKit

/// Single source of truth for the app. Every mutation writes through to
/// `SharedStore` (Keychain + shared defaults) so the widget extension sees the
/// same state, and reloads the widget timelines afterwards.
@MainActor
@Observable
final class AppStore {
    enum StoreError: LocalizedError {
        case noPortfolios

        var errorDescription: String? {
            switch self {
            case .noPortfolios: "No portfolios found on this Kubera account."
            }
        }
    }

    private(set) var credentials: KuberaCredentials?
    private(set) var portfolios: [PortfolioListItem] = []
    private(set) var selectedPortfolioId: String?
    private(set) var snapshot: PortfolioSnapshot?
    private(set) var settings: WidgetSettings
    private(set) var refreshing = false
    /// Observable mirrors of the widget data caches, so the in-app previews
    /// re-render the moment a refresh lands — they show exactly what the
    /// Home Screen widgets would show.
    private(set) var trends: PortfolioTrends?
    private(set) var comps: MarketComps?

    /// In-flight refresh, so the launch refresh and a pull-to-refresh don't
    /// both hit the API — the second caller awaits the first one's result.
    private var refreshTask: Task<Void, Error>?

    init() {
        SharedStore.migrateLegacyCredentialsIfNeeded()
        credentials = SharedStore.credentials()
        selectedPortfolioId = SharedStore.selectedPortfolioId()
        snapshot = SharedStore.cachedSnapshot()
        settings = SharedStore.settings()
        trends = SharedStore.cachedTrends()
        comps = SharedStore.cachedMarketComps()
    }

    // MARK: - Session

    func signIn(apiKey: String, secret: String, mcpToken: String = "") async throws {
        let trimmedToken = mcpToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let creds = KuberaCredentials(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secret.trimmingCharacters(in: .whitespacesAndNewlines),
            mcpToken: trimmedToken.isEmpty ? nil : trimmedToken
        )

        // Doubles as credential validation — throws on bad keys.
        let found = try await KuberaAPI.listPortfolios(creds: creds)
        guard let first = found.first else { throw StoreError.noPortfolios }

        credentials = creds
        portfolios = found
        SharedStore.saveCredentials(creds)

        selectedPortfolioId = first.id
        SharedStore.setSelectedPortfolioId(first.id)

        try await loadSnapshot(creds: creds, portfolioId: first.id)
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
        SharedStore.clearCredentials()
        SharedStore.setSelectedPortfolioId(nil)
        SharedStore.clearSnapshot()
        SharedStore.clearTrends()
        SharedStore.clearLocalHistory()
        reloadWidgets()
    }

    // MARK: - Data

    func refresh() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
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
    /// credentials and refreshes trends right away, so growth history from the
    /// API lights up without a re-sign-in.
    func saveMCPToken(_ token: String) async {
        guard var creds = credentials else { return }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        creds.mcpToken = trimmed.isEmpty ? nil : trimmed
        credentials = creds
        SharedStore.saveCredentials(creds)
        if let snapshot {
            await refreshTrends(creds: creds, snapshot: snapshot)
        }
        reloadWidgets()
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

        if portfolios.isEmpty {
            portfolios = try await KuberaAPI.listPortfolios(creds: creds)
        }
        try await loadSnapshot(creds: creds, portfolioId: portfolioId)
    }

    private func loadSnapshot(creds: KuberaCredentials, portfolioId: String) async throws {
        let fetched = try await KuberaAPI.fetchSnapshot(creds: creds, portfolioId: portfolioId)
        snapshot = fetched
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
        guard let refreshed else { return }
        trends = refreshed
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
