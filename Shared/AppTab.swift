import Foundation

/// The app's four tabs, named once so nothing has to agree by convention.
///
/// It lives here rather than inside `MainTabView` because two things outside the
/// view need to name a tab: the launch argument that opens the app on one, and
/// the scroll-to-top event that addresses one. Both are decisions rather than
/// layout, which is what makes them testable — the enum being private to the
/// view is what previously left the launch-argument mapping unreachable from the
/// test bundle.
///
/// The raw values are the launch argument's vocabulary, so renaming a case
/// changes a documented command.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case overview
    case assets
    case widgets
    case settings
}

extension AppTab {
    /// The tab a debug run asked to open on, from `-KuberaInitialTab`.
    ///
    /// Anything unrecognised — including nil, which is every normal launch —
    /// opens the Overview. A launch argument is a screenshot convenience, so a
    /// typo in one should start the app rather than fail it.
    static func initial(fromLaunchArgument raw: String?) -> AppTab {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let tab = AppTab(rawValue: raw) else {
            return .overview
        }
        return tab
    }
}

/// A request to scroll a tab's content back to the top, made by tapping the tab
/// bar item of the tab you are already on.
///
/// The serial is here for the same reason it is on `AssetsRequest`: the ask is
/// an event, not a state. Tapping Overview's tab item three times is three
/// requests naming the same tab, and each one has to move the screen — anything
/// watching a bare tab name would see no change after the first.
struct ScrollToTopRequest: Hashable, Sendable {
    let tab: AppTab
    let serial: Int

    /// The next request in a session. A serial only has to differ from its
    /// predecessor, so this counts rather than reaching for a UUID.
    static func next(after previous: ScrollToTopRequest?, tab: AppTab) -> ScrollToTopRequest {
        ScrollToTopRequest(tab: tab, serial: (previous?.serial ?? 0) + 1)
    }
}
