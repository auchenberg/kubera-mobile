import Foundation

/// Decides when the app requires re-authentication. Lives in Shared/ so the
/// unit-test bundle (which compiles Tests/ + Shared/ only) can exercise it;
/// the LAContext half stays in App/AppLock.swift.
enum AppLockPolicy {
    /// Brief backgrounding (app switching, a notification) shouldn't punish
    /// with a Face ID prompt; anything longer re-locks.
    static let gracePeriod: TimeInterval = 30

    static func shouldLock(enabled: Bool, backgroundedAt: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let backgroundedAt else { return true } // cold start
        return now.timeIntervalSince(backgroundedAt) >= gracePeriod
    }
}
