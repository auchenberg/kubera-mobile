import XCTest

final class AppLockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    func testDisabledNeverLocks() {
        XCTAssertFalse(AppLockPolicy.shouldLock(enabled: false, backgroundedAt: nil, now: now))
        XCTAssertFalse(AppLockPolicy.shouldLock(enabled: false, backgroundedAt: now.addingTimeInterval(-3600), now: now))
    }

    func testColdStartLocksWhenEnabled() {
        XCTAssertTrue(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: nil, now: now))
    }

    func testShortBackgroundingStaysUnlocked() {
        let backgrounded = now.addingTimeInterval(-AppLockPolicy.gracePeriod + 1)
        XCTAssertFalse(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: backgrounded, now: now))
    }

    func testGracePeriodBoundaryLocks() {
        let atBoundary = now.addingTimeInterval(-AppLockPolicy.gracePeriod)
        XCTAssertTrue(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: atBoundary, now: now))
        let past = now.addingTimeInterval(-AppLockPolicy.gracePeriod - 1)
        XCTAssertTrue(AppLockPolicy.shouldLock(enabled: true, backgroundedAt: past, now: now))
    }

    // MARK: - Settings decode compatibility

    func testSettingsWithoutLockKeyDecodeToEnabled() throws {
        let json = #"{"privacyMode":false,"showGain":true,"compactNumbers":true}"#
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.appLockEnabled, "pre-existing installs default to locked")
    }

    func testSettingsRoundTripLockDisabled() throws {
        var settings = WidgetSettings()
        settings.appLockEnabled = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: data)
        XCTAssertFalse(decoded.appLockEnabled)
    }
}
