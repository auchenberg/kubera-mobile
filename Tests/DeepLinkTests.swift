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
        XCTAssertEqual(DeepLink(url: DeepLink.overview(focus: nil).url), .overview(focus: nil))
    }

    // MARK: - What the widgets actually send

    func testWidgetURLsUseTheAppsScheme() {
        for focus in DeepLink.OverviewFocus.allCases {
            XCTAssertEqual(DeepLink.url(for: focus).scheme, DeepLink.scheme)
        }
        XCTAssertEqual(DeepLink.widgets.url.scheme, DeepLink.scheme)
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
    }

    func testTrailingSlashDoesNotHideTheFocus() {
        XCTAssertEqual(parse("kubera://overview/growth/"), .overview(focus: .growth))
    }
}
