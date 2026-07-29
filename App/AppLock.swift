import Foundation
import LocalAuthentication
import Observation

/// Owns the locked/unlocked state and talks to LocalAuthentication.
/// The when-to-lock policy lives in Shared/AppLockPolicy.swift (unit-tested).
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private var backgroundedAt: Date?

    init(enabled: Bool) {
        isLocked = enabled
    }

    func noteBackgrounded(now: Date = Date()) {
        backgroundedAt = now
    }

    func noteForegrounded(enabled: Bool, now: Date = Date()) {
        // scenePhase can go .active repeatedly without a backgrounding in
        // between (e.g. right after an unlock) — only judge real returns.
        guard let backgroundedAt else { return }
        if AppLockPolicy.shouldLock(enabled: enabled, backgroundedAt: backgroundedAt, now: now) {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    /// Biometrics with the system passcode as fallback. Devices without any
    /// protection configured unlock outright — a lock nobody can open would
    /// brick the app.
    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your portfolio"
            )
            if success { isLocked = false }
        } catch {
            // Cancelled or failed: stay locked; the user can retry.
        }
    }

    /// Turning the lock off unlocks the current session; turning it on starts
    /// enforcing on the next background/foreground cycle rather than
    /// immediately locking the person who just flipped the switch.
    func setEnabled(_ enabled: Bool) {
        if !enabled { isLocked = false }
    }
}
