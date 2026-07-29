import Foundation
import Security

/// Storage keys and models shared by the app and the widget extension.
/// The on-disk formats are live on user devices — changing a key or a JSON
/// shape orphans existing data, so treat them as fixed.
enum SharedKeys {
    static let appGroup = "group.com.auchenberg.kuberawidgets"
    /// Legacy NSUserDefaults location for credentials (pre-Keychain builds).
    static let legacyCredentials = "kubera.credentials"
    static let selectedPortfolioId = "kubera.selectedPortfolioId"
    static let settings = "kubera.settings"
    static let snapshot = "kubera.snapshot"
    static let trends = "kubera.trends"
    static let marketComps = "kubera.marketComps"
    static let localHistory = "kubera.localHistory"
    /// Human-readable outcome of the last history fetch, for the Settings card.
    static let historyStatus = "kubera.historyStatus"

    /// Keychain coordinates for credentials. Earlier builds wrote these items
    /// with expo-secure-store, which appends ":no-auth" to the service name and
    /// stores the account as raw UTF-8 bytes; both quirks are preserved here so
    /// items already on device keep resolving.
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

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        privacyMode = try container.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? false
        showGain = try container.decodeIfPresent(Bool.self, forKey: .showGain) ?? true
        compactNumbers = try container.decodeIfPresent(Bool.self, forKey: .compactNumbers) ?? true
        appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? true
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
}

/// Credential storage in the Keychain access group both targets share.
/// No kSecAttrAccessGroup is specified: reads search every access group the
/// caller is entitled to, and writes land in the default group — the first
/// entry in keychain-access-groups, which is the shared
/// `$(AppIdentifierPrefix)com.auchenberg.kuberawidgets.shared` group.
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
