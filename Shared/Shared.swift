import Foundation
import Security

/// Storage keys and models shared by the app and the widget extension.
/// The on-disk formats are live on user devices — changing a key or a JSON
/// shape orphans existing data, so treat them as fixed.
enum SharedKeys {
    static let appGroup = "group.com.kubera.mobile"
    /// Legacy NSUserDefaults location for credentials (pre-Keychain builds).
    static let legacyCredentials = "kubera.credentials"
    static let selectedPortfolioId = "kubera.selectedPortfolioId"
    static let settings = "kubera.settings"
    static let snapshot = "kubera.snapshot"
    static let trends = "kubera.trends"
    static let marketComps = "kubera.marketComps"
    /// Summary metrics and holdings from Kubera's MCP endpoint, which the
    /// REST snapshot does not carry.
    static let portfolioDetail = "kubera.portfolioDetail"
    static let profile = "kubera.profile"
    /// Kubera's own CAGR, from the `get_portfolio_cagr` tool. Its own key
    /// rather than a field on the detail blob: it comes from a separate tool
    /// with a separate failure, and one refresh may land without the other.
    static let portfolioCagr = "kubera.portfolioCagr"
    /// Which way of asking for the CAGR answered last time, so the argument
    /// probe is paid for once per device rather than once per refresh.
    static let cagrProbe = "kubera.cagrProbe"
    static let localHistory = "kubera.localHistory"
    /// Human-readable outcome of the last history fetch, for the Settings card.
    static let historyStatus = "kubera.historyStatus"

    /// Keychain coordinates for credentials. The service string and the
    /// bytes-not-string account attribute are inherited from the app's
    /// expo-secure-store era; they are kept because changing them buys nothing
    /// and would strand items written by any build that shipped before now.
    static let keychainService = "kubera-widgets:no-auth"
    static let keychainAccount = "kubera.credentials"
}

struct KuberaCredentials: Codable {
    let apiKey: String
    let secret: String
    /// Kubera issues a separate "MCP Token" (Settings → API) for its MCP
    /// endpoint — the only surface that serves portfolio history. Optional:
    /// items stored by builds that predate it decode with nil.
    var mcpToken: String? = nil
}

struct PortfolioListItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let currency: String
}

struct Holding: Codable, Hashable {
    let name: String
    let value: Double
    let sheet: String?
}

struct PortfolioSnapshot: Codable {
    let portfolioId: String
    let portfolioName: String
    let currency: String
    let netWorth: Double
    let assetTotal: Double
    let debtTotal: Double
    let costBasis: Double
    let unrealizedGain: Double
    let topHoldings: [Holding]
    let allocation: [String: Double]
    let updatedAt: Double
}

struct WidgetSettings: Codable {
    var privacyMode: Bool = false
    var showGain: Bool = true
    var compactNumbers: Bool = true
    /// Lock the app behind Face ID / passcode. On by default — settings blobs
    /// written before this key existed decode to true.
    var appLockEnabled: Bool = true
    /// The Overview blocks switched off, by their stable raw values. Hidden
    /// rather than visible on purpose: a module added in a later version is then
    /// visible by default rather than missing for everyone who saved a choice
    /// before it existed.
    var hiddenOverviewModules: Set<OverviewModule> = []

    /// Spelled out because providing both `init(from:)` and `encode(to:)` stops
    /// Swift synthesising them.
    private enum CodingKeys: String, CodingKey {
        case privacyMode, showGain, compactNumbers, appLockEnabled, hiddenOverviewModules
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        privacyMode = try container.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? false
        showGain = try container.decodeIfPresent(Bool.self, forKey: .showGain) ?? true
        compactNumbers = try container.decodeIfPresent(Bool.self, forKey: .compactNumbers) ?? true
        appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? true
        // An unknown raw value decodes to nil rather than throwing, so a blob
        // written by a newer build cannot make an older one fail to read its
        // settings at all.
        hiddenOverviewModules = Set(
            (try container.decodeIfPresent([String].self, forKey: .hiddenOverviewModules) ?? [])
                .compactMap(OverviewModule.init(rawValue:))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(privacyMode, forKey: .privacyMode)
        try container.encode(showGain, forKey: .showGain)
        try container.encode(compactNumbers, forKey: .compactNumbers)
        try container.encode(appLockEnabled, forKey: .appLockEnabled)
        // Sorted so an unchanged set encodes to identical bytes every time.
        try container.encode(hiddenOverviewModules.map(\.rawValue).sorted(), forKey: .hiddenOverviewModules)
    }
}

/// Reads and writes the NSUserDefaults suite shared by both targets.
/// Values are stored as JSON strings, not native plist types.
enum SharedStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedKeys.appGroup)
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let raw = defaults?.string(forKey: key), let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults?.set(raw, forKey: key)
    }

    // MARK: - Credentials

    static func credentials() -> KuberaCredentials? {
        if let creds = Keychain.credentials() {
            return creds
        }
        // Pre-Keychain builds stored credentials in the App Group defaults.
        // The app migrates them on next launch; until then, keep widgets
        // working by falling back to the old location.
        return decode(KuberaCredentials.self, forKey: SharedKeys.legacyCredentials)
    }

    /// Writes credentials to the shared Keychain and clears the legacy
    /// defaults copy, so the plaintext location never lingers.
    static func saveCredentials(_ creds: KuberaCredentials) {
        Keychain.save(credentials: creds)
        defaults?.removeObject(forKey: SharedKeys.legacyCredentials)
    }

    static func clearCredentials() {
        Keychain.deleteCredentials()
        defaults?.removeObject(forKey: SharedKeys.legacyCredentials)
    }

    /// Moves credentials left behind by pre-Keychain builds into the Keychain.
    /// Safe to call on every launch; a no-op once nothing is left to migrate.
    static func migrateLegacyCredentialsIfNeeded() {
        guard Keychain.credentials() == nil,
              let legacy = decode(KuberaCredentials.self, forKey: SharedKeys.legacyCredentials) else {
            return
        }
        Keychain.save(credentials: legacy)
        defaults?.removeObject(forKey: SharedKeys.legacyCredentials)
    }

    // MARK: - Selected portfolio

    static func selectedPortfolioId() -> String? {
        defaults?.string(forKey: SharedKeys.selectedPortfolioId)
    }

    static func setSelectedPortfolioId(_ id: String?) {
        guard let id else {
            defaults?.removeObject(forKey: SharedKeys.selectedPortfolioId)
            return
        }
        defaults?.set(id, forKey: SharedKeys.selectedPortfolioId)
    }

    // MARK: - Settings

    static func settings() -> WidgetSettings {
        decode(WidgetSettings.self, forKey: SharedKeys.settings) ?? WidgetSettings()
    }

    static func save(settings: WidgetSettings) {
        encode(settings, forKey: SharedKeys.settings)
    }

    // MARK: - Snapshot cache

    static func cachedSnapshot() -> PortfolioSnapshot? {
        decode(PortfolioSnapshot.self, forKey: SharedKeys.snapshot)
    }

    static func cache(snapshot: PortfolioSnapshot) {
        encode(snapshot, forKey: SharedKeys.snapshot)
    }

    static func clearSnapshot() {
        defaults?.removeObject(forKey: SharedKeys.snapshot)
    }

    // MARK: - Trends cache

    static func cachedTrends() -> PortfolioTrends? {
        decode(PortfolioTrends.self, forKey: SharedKeys.trends)
    }

    static func cache(trends: PortfolioTrends) {
        encode(trends, forKey: SharedKeys.trends)
    }

    static func clearTrends() {
        defaults?.removeObject(forKey: SharedKeys.trends)
    }

    // MARK: - Market comps cache

    static func cachedMarketComps() -> MarketComps? {
        decode(MarketComps.self, forKey: SharedKeys.marketComps)
    }

    static func cache(marketComps: MarketComps) {
        encode(marketComps, forKey: SharedKeys.marketComps)
    }

    static func clearMarketComps() {
        defaults?.removeObject(forKey: SharedKeys.marketComps)
    }

    // MARK: - Portfolio detail cache

    static func cachedDetail() -> PortfolioDetail? {
        decode(PortfolioDetail.self, forKey: SharedKeys.portfolioDetail)
    }

    static func cache(detail: PortfolioDetail) {
        encode(detail, forKey: SharedKeys.portfolioDetail)
    }

    static func clearDetail() {
        defaults?.removeObject(forKey: SharedKeys.portfolioDetail)
    }

    // MARK: - CAGR cache

    static func cachedCAGR() -> PortfolioCAGR? {
        decode(PortfolioCAGR.self, forKey: SharedKeys.portfolioCagr)
    }

    static func cache(cagr: PortfolioCAGR) {
        encode(cagr, forKey: SharedKeys.portfolioCagr)
    }

    static func clearCAGR() {
        defaults?.removeObject(forKey: SharedKeys.portfolioCagr)
    }

    static func cagrProbe() -> KuberaCAGRProbe? {
        decode(KuberaCAGRProbe.self, forKey: SharedKeys.cagrProbe)
    }

    static func save(cagrProbe probe: KuberaCAGRProbe) {
        encode(probe, forKey: SharedKeys.cagrProbe)
    }

    /// Forgets what the probe learned. Called when the credentials go away: a
    /// different account may have a different answer, and one stale memory
    /// would cost that account its figure until the memo aged out.
    static func clearCAGRProbe() {
        defaults?.removeObject(forKey: SharedKeys.cagrProbe)
    }

    // MARK: - Profile cache

    static func cachedProfile() -> KuberaProfile? {
        decode(KuberaProfile.self, forKey: SharedKeys.profile)
    }

    static func cache(profile: KuberaProfile) {
        encode(profile, forKey: SharedKeys.profile)
    }

    static func clearProfile() {
        defaults?.removeObject(forKey: SharedKeys.profile)
    }

    // MARK: - Local history log

    static func localHistory() -> [KuberaAPI.HistoryPoint] {
        decode([KuberaAPI.HistoryPoint].self, forKey: SharedKeys.localHistory) ?? []
    }

    /// Folds today's snapshot into the local history log (one point per day,
    /// the day's latest values win).
    static func record(historyPointFrom snapshot: PortfolioSnapshot, on day: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let point = KuberaAPI.HistoryPoint(
            date: formatter.string(from: day),
            value: snapshot.netWorth,
            assetTotal: snapshot.assetTotal,
            debtTotal: snapshot.debtTotal,
            investibleTotal: nil
        )
        encode(HistoryLog.appending(point, to: localHistory()), forKey: SharedKeys.localHistory)
    }

    /// Backfills the log from a server-fetched series so later offline
    /// refreshes keep their references. Points already recorded on device win
    /// on date collisions — they came from live snapshots.
    static func mergeLocalHistory(_ points: [KuberaAPI.HistoryPoint]) {
        var byDate: [String: KuberaAPI.HistoryPoint] = [:]
        for point in points { byDate[point.date] = point }
        for point in localHistory() { byDate[point.date] = point }
        let merged = byDate.values.sorted { $0.date < $1.date }.suffix(HistoryLog.cap)
        encode(Array(merged), forKey: SharedKeys.localHistory)
    }

    static func clearLocalHistory() {
        defaults?.removeObject(forKey: SharedKeys.localHistory)
    }

    // MARK: - History fetch status

    static func historyStatus() -> String? {
        defaults?.string(forKey: SharedKeys.historyStatus)
    }

    static func setHistoryStatus(_ status: String) {
        defaults?.set(status, forKey: SharedKeys.historyStatus)
    }

    /// Drops the last history outcome. Called when the MCP token changes or
    /// goes away, so the status line in Settings can't keep reporting a result
    /// that belonged to a different token.
    static func clearHistoryStatus() {
        defaults?.removeObject(forKey: SharedKeys.historyStatus)
    }
}

/// Credential storage in the Keychain access group both targets share.
/// No kSecAttrAccessGroup is specified: reads search every access group the
/// caller is entitled to, and writes land in the default group — the first
/// entry in keychain-access-groups, which is the shared
/// `$(AppIdentifierPrefix)com.kubera.mobile.shared` group.
enum Keychain {
    static func credentials() -> KuberaCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(KuberaCredentials.self, from: data)
    }

    /// Replaces any stored credentials. Accessible after first unlock so
    /// widget timeline refreshes can read them while the device is locked.
    @discardableResult
    static func save(credentials: KuberaCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }

        deleteCredentials()

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteCredentials() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// The account is passed as UTF-8 bytes rather than a string because that
    /// is how expo-secure-store wrote it; a String query would not match.
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedKeys.keychainService,
            kSecAttrAccount as String: Data(SharedKeys.keychainAccount.utf8),
        ]
    }
}

extension PortfolioSnapshot {
    static let sample = PortfolioSnapshot(
        portfolioId: "sample",
        portfolioName: "Main portfolio",
        currency: "USD",
        netWorth: 1_240_000,
        assetTotal: 1_610_000,
        debtTotal: 370_000,
        costBasis: 1_026_000,
        unrealizedGain: 214_000,
        topHoldings: [
            Holding(name: "Index funds", value: 620_000, sheet: "Investments"),
            Holding(name: "Home", value: 450_000, sheet: "Real estate"),
            Holding(name: "Bitcoin", value: 96_000, sheet: "Crypto"),
            Holding(name: "Cash", value: 74_000, sheet: "Banks"),
        ],
        allocation: ["Investable": 64, "Real estate": 28, "Crypto": 8],
        updatedAt: Date().timeIntervalSince1970
    )
}
