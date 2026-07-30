import Foundation

/// The blocks the Overview can show below its hero figure, and which of them the
/// user has switched off.
///
/// Lives here rather than beside the view so the set can be persisted with the
/// rest of `WidgetSettings` and unit-tested — the interesting part is not the
/// menu, it is that hiding a module has to survive a new version of the app
/// adding one.
enum OverviewModule: String, CaseIterable, Codable, Identifiable, Sendable {
    case assetsDebts
    case balances
    case growth
    case allocation
    case assetFlow
    case composition
    case holdings

    var id: String { rawValue }

    /// Menu label. Matches the section heading on the screen wherever there is
    /// one, so the thing you switch off is named the same as the thing that
    /// disappears.
    var title: String {
        switch self {
        case .assetsDebts: "Assets & debts"
        case .balances: "Cash & tax"
        case .growth: "CAGR • YTD"
        case .allocation: "Allocation"
        case .assetFlow: "Asset flow"
        case .composition: "Composition"
        case .holdings: "Top holdings"
        }
    }

    /// The net worth hero is deliberately absent from this list. It is the
    /// screen's reason to exist, and a dashboard that can be emptied entirely
    /// is a blank page with a menu on it.
    static var hideable: [OverviewModule] { allCases }
}

extension Set where Element == OverviewModule {
    /// Stored as the *hidden* set rather than the visible one, so a module added
    /// in a later version defaults to visible instead of silently missing for
    /// everyone who saved their choices before it existed.
    func shows(_ module: OverviewModule) -> Bool { !contains(module) }

    mutating func setVisibility(_ visible: Bool, for module: OverviewModule) {
        if visible {
            remove(module)
        } else {
            insert(module)
        }
    }
}
