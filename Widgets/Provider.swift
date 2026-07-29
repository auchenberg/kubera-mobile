import WidgetKit

struct KuberaEntry: TimelineEntry {
    enum State {
        case signedOut
        case data(PortfolioSnapshot)
    }

    let date: Date
    let state: State
    let settings: WidgetSettings
    /// Nil whenever history is unavailable; widgets drop their stat rows rather
    /// than failing, so a trends outage never blanks a timeline.
    let trends: PortfolioTrends?
    /// Market benchmarks shown beside the user's own growth. Nil when they have
    /// never been fetched; like trends, an outage only costs the comps row.
    let comps: MarketComps?

    static var sample: KuberaEntry {
        KuberaEntry(
            date: Date(),
            state: .data(.sample),
            settings: WidgetSettings(),
            trends: .sample,
            comps: .sample
        )
    }
}

/// One provider drives every widget kind: it renders the cached snapshot
/// instantly and refreshes from the Kubera API in the timeline pass.
struct KuberaProvider: TimelineProvider {
    func placeholder(in context: Context) -> KuberaEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (KuberaEntry) -> Void) {
        if context.isPreview {
            // Widget gallery: show real data when available, sample otherwise.
            if let cached = SharedStore.cachedSnapshot() {
                completion(KuberaEntry(
                    date: Date(),
                    state: .data(cached),
                    settings: SharedStore.settings(),
                    trends: SharedStore.cachedTrends(),
                    comps: SharedStore.cachedMarketComps()
                ))
            } else {
                completion(.sample)
            }
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KuberaEntry>) -> Void) {
        guard let creds = SharedStore.credentials() else {
            let entry = KuberaEntry(
                date: Date(),
                state: .signedOut,
                settings: SharedStore.settings(),
                trends: nil,
                comps: nil
            )
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
            return
        }

        // Reloads triggered by the app (a settings toggle, or right after the
        // app refreshed) should render instantly from the cache the app just
        // wrote — a full network pass here made even privacy mode take ~seconds
        // to reflect. The network path is for the periodic self-refresh, when
        // the cache has actually gone stale.
        if let cached = SharedStore.cachedSnapshot(),
           Date().timeIntervalSince1970 - cached.updatedAt < 10 * 60 {
            let entry = KuberaEntry(
                date: Date(),
                state: .data(cached),
                settings: SharedStore.settings(),
                trends: SharedStore.cachedTrends(),
                comps: SharedStore.cachedMarketComps()
            )
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
            return
        }

        Task {
            let settings = SharedStore.settings()
            do {
                let snapshot = try await KuberaAPI.fetchSnapshot(
                    creds: creds,
                    portfolioId: SharedStore.selectedPortfolioId()
                )
                SharedStore.cache(snapshot: snapshot)
                let trends = await refreshedTrends(creds: creds, snapshot: snapshot)
                let comps = await refreshedComps()
                let entry = KuberaEntry(
                    date: Date(),
                    state: .data(snapshot),
                    settings: settings,
                    trends: trends,
                    comps: comps
                )
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
            } catch {
                // Network or auth failure: keep showing the cached numbers and retry sooner.
                let entry = currentEntry()
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
            }
        }
    }

    /// History is a second network round trip and strictly optional decoration,
    /// so every failure path quietly degrades to the last computed trends.
    private func refreshedTrends(creds: KuberaCredentials, snapshot: PortfolioSnapshot) async -> PortfolioTrends? {
        await TrendsCalculator.refresh(creds: creds, snapshot: snapshot)
    }

    private func refreshedComps() async -> MarketComps? {
        await MarketCompsFetcher.cachedOrFresh()
    }

    private func currentEntry() -> KuberaEntry {
        let settings = SharedStore.settings()
        guard SharedStore.credentials() != nil else {
            return KuberaEntry(date: Date(), state: .signedOut, settings: settings, trends: nil, comps: nil)
        }
        if let cached = SharedStore.cachedSnapshot() {
            return KuberaEntry(
                date: Date(),
                state: .data(cached),
                settings: settings,
                trends: SharedStore.cachedTrends(),
                comps: SharedStore.cachedMarketComps()
            )
        }
        return KuberaEntry(date: Date(), state: .signedOut, settings: settings, trends: nil, comps: nil)
    }
}
