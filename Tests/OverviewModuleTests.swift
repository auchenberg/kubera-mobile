import XCTest

final class OverviewModuleTests: XCTestCase {
    // MARK: - Visibility

    func testEverythingIsVisibleByDefault() {
        let settings = WidgetSettings()
        for module in OverviewModule.allCases {
            XCTAssertTrue(settings.hiddenOverviewModules.shows(module), "\(module) started hidden")
        }
    }

    func testHidingAndShowingAModule() {
        var hidden: Set<OverviewModule> = []

        hidden.setVisibility(false, for: .composition)
        XCTAssertFalse(hidden.shows(.composition))
        XCTAssertTrue(hidden.shows(.allocation), "hiding one must not touch another")

        hidden.setVisibility(true, for: .composition)
        XCTAssertTrue(hidden.shows(.composition))
    }

    func testSettingTheSameVisibilityTwiceIsHarmless() {
        var hidden: Set<OverviewModule> = []
        hidden.setVisibility(false, for: .growth)
        hidden.setVisibility(false, for: .growth)
        XCTAssertEqual(hidden, [.growth])

        hidden.setVisibility(true, for: .growth)
        hidden.setVisibility(true, for: .growth)
        XCTAssertTrue(hidden.isEmpty)
    }

    func testEveryModuleHasANonEmptyTitleAndTheyAreDistinct() {
        let titles = OverviewModule.allCases.map(\.title)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
        XCTAssertEqual(Set(titles).count, titles.count, "two menu rows would read the same")
    }

    // MARK: - Persistence

    private func roundTrip(_ settings: WidgetSettings) throws -> WidgetSettings {
        let data = try JSONEncoder().encode(settings)
        return try JSONDecoder().decode(WidgetSettings.self, from: data)
    }

    func testHiddenModulesSurviveARoundTrip() throws {
        var settings = WidgetSettings()
        settings.hiddenOverviewModules = [.assetFlow, .holdings]

        XCTAssertEqual(try roundTrip(settings).hiddenOverviewModules, [.assetFlow, .holdings])
    }

    func testTheOtherSettingsStillSurviveARoundTrip() throws {
        var settings = WidgetSettings()
        settings.privacyMode = true
        settings.compactNumbers = false
        settings.appLockEnabled = false

        let decoded = try roundTrip(settings)

        XCTAssertTrue(decoded.privacyMode)
        XCTAssertFalse(decoded.compactNumbers)
        XCTAssertFalse(decoded.appLockEnabled)
    }

    func testTheHiddenListEncodesInASortedOrder() throws {
        var settings = WidgetSettings()
        settings.hiddenOverviewModules = [.holdings, .growth, .allocation]

        // A Set has no stable iteration order, so without sorting on encode the
        // same settings would serialise differently run to run. Only the array
        // is asserted: JSONEncoder decides the order of the object's own keys,
        // which is not something this type controls.
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(settings)
        ) as? [String: Any]
        let hidden = json?["hiddenOverviewModules"] as? [String]

        XCTAssertEqual(hidden, ["allocation", "growth", "holdings"])
        XCTAssertEqual(hidden, hidden?.sorted())
    }

    // MARK: - Compatibility, in both directions

    func testSettingsWrittenBeforeThisFeatureDecodeWithNothingHidden() throws {
        // A blob from a build that had no such key at all.
        let old = Data("""
        {"privacyMode":true,"showGain":true,"compactNumbers":true,"appLockEnabled":true}
        """.utf8)

        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: old)

        XCTAssertTrue(decoded.hiddenOverviewModules.isEmpty, "an upgrade must not hide anything")
        XCTAssertTrue(decoded.privacyMode)
    }

    func testAModuleThisBuildDoesNotKnowIsIgnoredRatherThanFatal() throws {
        // Written by a newer build that added a module this one has never heard
        // of. Decoding must not throw, or an older build cannot read its own
        // settings at all — it would lose Face ID and Privacy mode too.
        let newer = Data("""
        {"privacyMode":true,"appLockEnabled":true,
         "hiddenOverviewModules":["composition","somethingFromTheFuture"]}
        """.utf8)

        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: newer)

        XCTAssertEqual(decoded.hiddenOverviewModules, [.composition])
        XCTAssertTrue(decoded.privacyMode, "the rest of the settings must survive too")
    }

    func testRawValuesAreStableBecauseTheyArePersisted() {
        // Renaming a case would silently un-hide whatever a user had hidden.
        XCTAssertEqual(
            Set(OverviewModule.allCases.map(\.rawValue)),
            ["assetsDebts", "balances", "growth", "allocation", "assetFlow", "composition", "holdings"]
        )
    }
}
