import XCTest

final class DeepLinkTests: XCTestCase {
    private func parse(_ string: String) -> DeepLink {
        DeepLink(url: URL(string: string)!)
    }

    // MARK: - Round trip

    func testEveryFocusRoundTripsThroughItsURL() {
        for focus in DeepLink.OverviewFocus.allCases {
            let url = DeepLink.url(for: focus)
            XCTAssertEqual(DeepLink(url: url), .overview(focus: focus), "broke on \(focus)")
        }
    }

    func testTabsRoundTrip() {
        XCTAssertEqual(DeepLink(url: DeepLink.widgets.url), .widgets)
        XCTAssertEqual(DeepLink(url: DeepLink.settings.url), .settings)
        XCTAssertEqual(DeepLink(url: DeepLink.assets.url), .assets)
        XCTAssertEqual(DeepLink(url: DeepLink.overview(focus: nil).url), .overview(focus: nil))
    }

    /// Every destination the app routes, in one list: the app switches over all
    /// of them, so one that does not survive its own URL sends the reader to the
    /// wrong tab rather than failing.
    func testEveryDestinationSurvivesItsOwnURL() {
        let destinations: [DeepLink] = [
            .overview(focus: nil),
            .overview(focus: .netWorth),
            .assets,
            .widgets,
            .settings,
        ]

        for destination in destinations {
            XCTAssertEqual(DeepLink(url: destination.url), destination, "broke on \(destination)")
        }
        XCTAssertEqual(Set(destinations.map(\.url)).count, destinations.count, "two destinations share a URL")
    }

    // MARK: - What the widgets actually send

    func testWidgetURLsUseTheAppsScheme() {
        for focus in DeepLink.OverviewFocus.allCases {
            XCTAssertEqual(DeepLink.url(for: focus).scheme, DeepLink.scheme)
        }
        XCTAssertEqual(DeepLink.widgets.url.scheme, DeepLink.scheme)
        XCTAssertEqual(DeepLink.assets.url.scheme, DeepLink.scheme)
    }

    /// The Assets vs Debts widget now sends this instead of the Overview focus.
    /// The focus itself is deliberately still routable: a widget already on a
    /// Home Screen keeps sending the URL it was built with until its timeline
    /// reloads, and that URL must keep landing on the module it names.
    func testTheAssetsLinkAndTheOldAssetsDebtsFocusBothStillRoute() {
        XCTAssertEqual(parse("kubera://assets"), .assets)
        XCTAssertEqual(parse("kubera://overview/assetsDebts"), .overview(focus: .assetsDebts))
        XCTAssertNotEqual(DeepLink.assets.url, DeepLink.url(for: .assetsDebts))
    }

    func testAnchorsAreDistinctSoModulesCannotCollide() {
        let anchors = Set(DeepLink.OverviewFocus.allCases.map(\.anchor))
        XCTAssertEqual(anchors.count, DeepLink.OverviewFocus.allCases.count)
    }

    // MARK: - Tolerance

    func testBareSchemeStillOpensTheOverview() {
        // What a widget placed before this change still sends. It has to keep
        // working, just without a focus.
        XCTAssertEqual(parse("kubera://"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview"), .overview(focus: nil))
    }

    func testUnknownHostsAndPathsFallBackToTheOverview() {
        XCTAssertEqual(parse("kubera://somethingelse"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview/notamodule"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview/netWorth/extra"), .overview(focus: .netWorth))
    }

    func testHostMatchingIgnoresCase() {
        XCTAssertEqual(parse("kubera://Settings"), .settings)
        XCTAssertEqual(parse("kubera://WIDGETS"), .widgets)
        XCTAssertEqual(parse("kubera://Assets"), .assets)
    }

    /// The new host must not have opened a hole in the fallback: anything that
    /// merely looks like it still lands on the Overview rather than nowhere.
    func testNearMissesForTheAssetsHostStillFallBack() {
        XCTAssertEqual(parse("kubera://asset"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://assetsdebts"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview/assets"), .overview(focus: nil))
    }

    func testTrailingSlashDoesNotHideTheFocus() {
        XCTAssertEqual(parse("kubera://overview/growth/"), .overview(focus: .growth))
    }
}

// MARK: - Asking for the assets tab

/// `AssetsRequest` is what a widget URL and a tap on the Overview both turn
/// into, so the app has one route to the assets tab rather than one per caller.
/// Its whole job is to be *noticed*: the screen reacts to the request changing,
/// which is why the serial exists and why these tests are about inequality.
final class AssetsRequestTests: XCTestCase {
    func testARequestCarriesTheSheetItWasMadeFor() {
        XCTAssertEqual(AssetsRequest.next(after: nil, sheetID: "Crypto").sheetID, "Crypto")
        XCTAssertNil(AssetsRequest.next(after: nil, sheetID: nil).sheetID, "a bare request names no sheet")
    }

    /// The bug this type exists to prevent: tapping "Crypto", going elsewhere,
    /// and tapping "Crypto" again must move the screen the second time too.
    /// Watching a bare sheet name would see no change and sit still.
    func testTwoRequestsForTheSameSheetAreDifferentRequests() {
        let first = AssetsRequest.next(after: nil, sheetID: "Crypto")
        let second = AssetsRequest.next(after: first, sheetID: "Crypto")

        XCTAssertEqual(first.sheetID, second.sheetID)
        XCTAssertNotEqual(first, second)
    }

    func testSerialsAdvanceThroughASession() {
        var request: AssetsRequest?
        var seen: [AssetsRequest] = []
        for sheet in ["Crypto", "Crypto", nil, "Investments", nil] {
            request = AssetsRequest.next(after: request, sheetID: sheet)
            seen.append(request!)
        }

        XCTAssertEqual(seen.map(\.serial), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(seen).count, seen.count, "two requests in one session were indistinguishable")
    }

    /// Equality is still value equality — the serial is the only thing that
    /// makes two same-sheet requests differ, not an identity that would make
    /// every comparison false.
    func testTwoRequestsWithTheSameSerialAndSheetAreEqual() {
        XCTAssertEqual(AssetsRequest(sheetID: "Crypto", serial: 3), AssetsRequest(sheetID: "Crypto", serial: 3))
        XCTAssertNotEqual(AssetsRequest(sheetID: "Crypto", serial: 3), AssetsRequest(sheetID: "Banks", serial: 3))
    }
}
