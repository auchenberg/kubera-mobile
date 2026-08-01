import XCTest

/// `AppTab` exists outside the view so these two decisions can be tested: which
/// tab a debug launch opens on, and what a tap on an already-selected tab bar
/// item turns into. Both used to live inside `MainTabView`, where the test
/// bundle could not reach them.
final class AppTabTests: XCTestCase {
    // MARK: - The launch argument

    func testEveryTabCanBeAskedForByName() {
        for tab in AppTab.allCases {
            XCTAssertEqual(AppTab.initial(fromLaunchArgument: tab.rawValue), tab)
        }
    }

    /// A launch argument is a screenshot convenience, so a typo has to start the
    /// app rather than fail it — including the nil case, which is every normal
    /// launch.
    func testAnythingUnrecognisedOpensTheOverview() {
        for argument in [nil, "", "   ", "dashboard", "Assets tab", "nonsense"] {
            XCTAssertEqual(
                AppTab.initial(fromLaunchArgument: argument),
                .overview,
                "\(argument ?? "nil") should have opened the Overview"
            )
        }
    }

    /// Typed by hand into a shell command, so the case and the spacing a shell
    /// leaves behind must not decide whether it works.
    func testTheArgumentIsReadLenientlyAboutCaseAndSpace() {
        XCTAssertEqual(AppTab.initial(fromLaunchArgument: "ASSETS"), .assets)
        XCTAssertEqual(AppTab.initial(fromLaunchArgument: "Widgets"), .widgets)
        XCTAssertEqual(AppTab.initial(fromLaunchArgument: " settings "), .settings)
    }

    /// The raw values are a documented command's vocabulary — renaming a case
    /// silently breaks `-KuberaInitialTab <name>` for whoever scripted it.
    func testTheArgumentVocabularyIsStable() {
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["overview", "assets", "widgets", "settings"])
    }

    // MARK: - Scrolling back to the top

    func testARequestNamesTheTabThatAskedForIt() {
        XCTAssertEqual(ScrollToTopRequest.next(after: nil, tab: .settings).tab, .settings)
    }

    /// The point of the serial: three taps on the Overview's tab bar item are
    /// three requests naming one tab, and each has to move the screen. A watcher
    /// looking at a bare tab name would see no change after the first.
    func testRepeatedTapsOnOneTabAreDistinctRequests() {
        let first = ScrollToTopRequest.next(after: nil, tab: .overview)
        let second = ScrollToTopRequest.next(after: first, tab: .overview)
        let third = ScrollToTopRequest.next(after: second, tab: .overview)

        XCTAssertEqual(Set([first, second, third]).count, 3)
        XCTAssertEqual([first, second, third].map(\.serial), [1, 2, 3])
        XCTAssertTrue([first, second, third].allSatisfy { $0.tab == .overview })
    }

    /// Serials advance across tabs rather than per tab, so a request is never
    /// mistaken for an earlier one made somewhere else.
    func testSerialsAdvanceAcrossTabs() {
        var request: ScrollToTopRequest?
        var seen: [ScrollToTopRequest] = []
        for tab in [AppTab.overview, .assets, .assets, .widgets, .overview] {
            request = .next(after: request, tab: tab)
            seen.append(request!)
        }

        XCTAssertEqual(seen.map(\.serial), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(seen).count, seen.count)
    }

    /// Equality stays value equality: the serial is what separates two requests
    /// for one tab, not an identity that would make every comparison false.
    func testTwoRequestsWithTheSameTabAndSerialAreEqual() {
        XCTAssertEqual(ScrollToTopRequest(tab: .assets, serial: 2), ScrollToTopRequest(tab: .assets, serial: 2))
        XCTAssertNotEqual(ScrollToTopRequest(tab: .assets, serial: 2), ScrollToTopRequest(tab: .widgets, serial: 2))
    }
}
