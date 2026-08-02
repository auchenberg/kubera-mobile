import Foundation

/// The URLs widgets open and the app routes. Shared so the two halves cannot
/// disagree: a widget writing a host the app does not recognise would still open
/// the app, just at the wrong place, and nothing would fail loudly.
/// A request to show one side of the portfolio — the Assets tab or the Debts one
/// — made either by a widget's `kubera://assets` / `kubera://debts` or by a tap
/// on the Overview. One type for every route into either screen, so a tap and a
/// widget cannot end up behaving differently; the URL simply arrives with no
/// sheet.
///
/// The serial is what makes this a *request* rather than a value. Tapping
/// "Crypto" on the Overview, wandering off, and tapping it again is two requests
/// carrying the same sheet, and the second has to move the screen as surely as
/// the first; anything watching a bare sheet name would see no change and sit
/// still.
struct BookRequest: Hashable, Sendable {
    /// Which screen is being asked for. A screen answers only requests naming
    /// its own side, so one channel serves both without either eavesdropping.
    let side: PortfolioSide
    /// The sheet to open on, or nil for "just show me that screen", which leaves
    /// whatever sheet is already selected alone.
    let sheetID: String?
    /// Distinguishes this request from the one before it, and nothing more.
    let serial: Int

    /// The next request in a session. A serial only has to differ from its
    /// predecessor, so this counts rather than reaching for a UUID.
    static func next(
        after previous: BookRequest?,
        side: PortfolioSide,
        sheetID: String?
    ) -> BookRequest {
        BookRequest(side: side, sheetID: sheetID, serial: (previous?.serial ?? 0) + 1)
    }
}

enum DeepLink: Equatable {
    /// A tab to show, and optionally a module on the Overview to bring into view.
    case overview(focus: OverviewFocus?)
    /// One side's drill-down: sheets, sections and the rows inside them.
    case book(PortfolioSide)
    case widgets
    case settings

    /// Which module on the Overview a widget corresponds to, so tapping a widget
    /// lands on the figure it was showing rather than the top of the screen.
    ///
    /// `assetsDebts` outlives the widget that used to send it: a widget already
    /// on someone's Home Screen keeps handing over the URL it was built with
    /// until its timeline reloads, and that URL has to keep landing somewhere
    /// sensible. The Overview still anchors the module it names.
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
        case let .book(side): return URL(string: "\(Self.scheme)://\(side.rawValue)")!
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
        case let host? where PortfolioSide(rawValue: host) != nil:
            // Table-driven rather than a case per side, so a side added to the
            // model is routable without touching this switch.
            self = .book(PortfolioSide(rawValue: host)!)
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
