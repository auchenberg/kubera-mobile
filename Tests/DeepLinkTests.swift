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
        XCTAssertEqual(DeepLink(url: DeepLink.book(.assets).url), .book(.assets))
        XCTAssertEqual(DeepLink(url: DeepLink.book(.debts).url), .book(.debts))
        XCTAssertEqual(DeepLink(url: DeepLink.overview(focus: nil).url), .overview(focus: nil))
    }

    /// Every destination the app routes, in one list: the app switches over all
    /// of them, so one that does not survive its own URL sends the reader to the
    /// wrong tab rather than failing.
    func testEveryDestinationSurvivesItsOwnURL() {
        let destinations: [DeepLink] = [
            .overview(focus: nil),
            .overview(focus: .netWorth),
            .book(.assets),
            .book(.debts),
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
        for side in PortfolioSide.allCases {
            XCTAssertEqual(DeepLink.book(side).url.scheme, DeepLink.scheme)
        }
    }

    /// The Assets vs Debts widget now sends this instead of the Overview focus.
    /// The focus itself is deliberately still routable: a widget already on a
    /// Home Screen keeps sending the URL it was built with until its timeline
    /// reloads, and that URL must keep landing on the module it names.
    func testTheBookLinksAndTheOldAssetsDebtsFocusAllStillRoute() {
        XCTAssertEqual(parse("kubera://assets"), .book(.assets))
        XCTAssertEqual(parse("kubera://debts"), .book(.debts))
        XCTAssertEqual(parse("kubera://overview/assetsDebts"), .overview(focus: .assetsDebts))
        XCTAssertNotEqual(DeepLink.book(.assets).url, DeepLink.url(for: .assetsDebts))
    }

    /// Every side the model knows is routable by name, so a side added to
    /// `PortfolioSide` cannot end up with a URL nothing answers.
    func testEverySideIsRoutableByItsOwnName() {
        for side in PortfolioSide.allCases {
            XCTAssertEqual(parse("kubera://\(side.rawValue)"), .book(side), side.rawValue)
        }
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
        XCTAssertEqual(parse("kubera://Assets"), .book(.assets))
        XCTAssertEqual(parse("kubera://DEBTS"), .book(.debts))
    }

    /// The new host must not have opened a hole in the fallback: anything that
    /// merely looks like it still lands on the Overview rather than nowhere.
    func testNearMissesForTheAssetsHostStillFallBack() {
        XCTAssertEqual(parse("kubera://asset"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://debt"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://assetsdebts"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview/assets"), .overview(focus: nil))
        XCTAssertEqual(parse("kubera://overview/debts"), .overview(focus: nil))
    }

    func testTrailingSlashDoesNotHideTheFocus() {
        XCTAssertEqual(parse("kubera://overview/growth/"), .overview(focus: .growth))
    }
}

// MARK: - Asking for the assets tab

/// `BookRequest` is what a widget URL and a tap on the Overview both turn into,
/// so the app has one route into either book screen rather than one per caller.
/// Its whole job is to be *noticed*: the screen reacts to the request changing,
/// which is why the serial exists and why these tests are about inequality.
final class BookRequestTests: XCTestCase {
    func testARequestCarriesTheSideAndSheetItWasMadeFor() {
        let request = BookRequest.next(after: nil, side: .debts, sheetID: "Loans")

        XCTAssertEqual(request.side, .debts)
        XCTAssertEqual(request.sheetID, "Loans")
        XCTAssertNil(
            BookRequest.next(after: nil, side: .assets, sheetID: nil).sheetID,
            "a bare request names no sheet"
        )
    }

    /// The two screens share one channel, so a request has to be refusable: the
    /// Debts screen must not move because somebody asked for Crypto.
    func testARequestNamesOneSideOnly() {
        let assets = BookRequest.next(after: nil, side: .assets, sheetID: "Crypto")
        let debts = BookRequest.next(after: assets, side: .debts, sheetID: "Loans")

        XCTAssertNotEqual(assets.side, debts.side)
        XCTAssertEqual(Set([assets, debts]).count, 2)
    }

    /// The bug this type exists to prevent: tapping "Crypto", going elsewhere,
    /// and tapping "Crypto" again must move the screen the second time too.
    /// Watching a bare sheet name would see no change and sit still.
    func testTwoRequestsForTheSameSheetAreDifferentRequests() {
        let first = BookRequest.next(after: nil, side: .assets, sheetID: "Crypto")
        let second = BookRequest.next(after: first, side: .assets, sheetID: "Crypto")

        XCTAssertEqual(first.sheetID, second.sheetID)
        XCTAssertNotEqual(first, second)
    }

    func testSerialsAdvanceThroughASession() {
        var request: BookRequest?
        var seen: [BookRequest] = []
        for (side, sheet) in [
            (PortfolioSide.assets, "Crypto"), (.assets, "Crypto"), (.debts, nil),
            (.assets, "Investments"), (.debts, nil),
        ] as [(PortfolioSide, String?)] {
            request = BookRequest.next(after: request, side: side, sheetID: sheet)
            seen.append(request!)
        }

        XCTAssertEqual(seen.map(\.serial), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(seen).count, seen.count, "two requests in one session were indistinguishable")
    }

    /// Equality is still value equality — the serial is the only thing that
    /// makes two same-sheet requests differ, not an identity that would make
    /// every comparison false.
    func testTwoRequestsWithTheSameSerialAndSheetAreEqual() {
        XCTAssertEqual(
            BookRequest(side: .assets, sheetID: "Crypto", serial: 3),
            BookRequest(side: .assets, sheetID: "Crypto", serial: 3)
        )
        XCTAssertNotEqual(
            BookRequest(side: .assets, sheetID: "Crypto", serial: 3),
            BookRequest(side: .debts, sheetID: "Crypto", serial: 3)
        )
    }
}
