import Foundation

/// The URLs widgets open and the app routes. Shared so the two halves cannot
/// disagree: a widget writing a host the app does not recognise would still open
/// the app, just at the wrong place, and nothing would fail loudly.
enum DeepLink: Equatable {
    /// A tab to show, and optionally a module on the Overview to bring into view.
    case overview(focus: OverviewFocus?)
    case widgets
    case settings

    /// Which module on the Overview a widget corresponds to, so tapping a widget
    /// lands on the figure it was showing rather than the top of the screen.
    enum OverviewFocus: String, Equatable, CaseIterable {
        case netWorth
        case growth
        case assetsDebts

        /// The scroll anchor the Overview attaches to the matching module.
        var anchor: String { "focus.\(rawValue)" }
    }

    static let scheme = "kubera"

    // MARK: - Writing

    /// The URL a widget hands to `widgetURL`.
    static func url(for focus: OverviewFocus?) -> URL {
        guard let focus else { return URL(string: "\(scheme)://overview")! }
        return URL(string: "\(scheme)://overview/\(focus.rawValue)")!
    }

    var url: URL {
        switch self {
        case let .overview(focus): return Self.url(for: focus)
        case .widgets: return URL(string: "\(Self.scheme)://widgets")!
        case .settings: return URL(string: "\(Self.scheme)://settings")!
        }
    }

    // MARK: - Reading

    /// Parses a URL the system hands to `onOpenURL`. Unknown hosts fall back to
    /// the Overview with no focus, which is what a bare `kubera://` from an older
    /// widget still installed on the Home Screen resolves to — those keep working
    /// rather than opening nothing.
    init(url: URL) {
        switch url.host()?.lowercased() {
        case "widgets":
            self = .widgets
        case "settings":
            self = .settings
        default:
            let segment = url.pathComponents.first { $0 != "/" }
            self = .overview(focus: segment.flatMap(OverviewFocus.init(rawValue:)))
        }
    }
}
