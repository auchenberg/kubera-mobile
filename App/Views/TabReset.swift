import SwiftUI

/// Putting a tab back the way it was first seen.
///
/// Tapping the tab bar item of the tab you are already on is iOS's "reset this"
/// gesture. `MainTabView` turns that tap into a `TabResetRequest` and publishes
/// it here; everything else in this file is how a view says what it does about
/// one.
///
/// **The design goal is that nothing here knows what any screen resets.** A view
/// declares its own behaviour with `onTabReset(of:perform:)`, next to the state
/// it owns, and that is the whole contract — the tab bar has no list of screens,
/// no switch over tabs, and no idea that the Assets screen has a sheet switcher.
/// Adding a reset to a new tab, or to one more piece of state on an existing
/// one, is one modifier at that state's own site and no change to this file or
/// to `MainTabView`.
///
/// `scrollsToTopOnTabReset(of:)` is not a second mechanism but the first
/// participant, written in terms of `onTabReset` like any other — it is only
/// pre-built because every tab wants it.
///
/// Participants are independent: several may answer one request, they all run in
/// the same turn, and none may depend on another having gone first.

extension EnvironmentValues {
    /// The most recent ask to put a tab back. Nil in previews and anywhere
    /// outside the tab bar, where a screen is never asked to reset itself.
    var tabResetRequest: TabResetRequest? {
        get { self[TabResetRequestKey.self] }
        set { self[TabResetRequestKey.self] = newValue }
    }
}

private struct TabResetRequestKey: EnvironmentKey {
    static let defaultValue: TabResetRequest? = nil
}

extension View {
    /// Runs `action` when `tab`'s tab bar item is tapped while that tab is
    /// already showing.
    ///
    /// Declare it beside the state it puts back, at whatever depth that state
    /// lives — the request arrives through the environment, so a row buried
    /// inside a card can answer one as directly as a tab's root view.
    ///
    /// The action runs inside an animation, so participants describe *what* is
    /// restored and never how it should move; Reduce Motion drops the travel
    /// without dropping the reset.
    func onTabReset(of tab: AppTab, perform action: @escaping () -> Void) -> some View {
        modifier(TabResetResponder(tab: tab, action: action))
    }

    /// Marks this view as the top of its tab's scrolling content — where
    /// `scrollsToTopOnTabReset(of:)` scrolls back to. One per scroll view.
    func tabTopAnchor() -> some View {
        id(TabResetAnchor.top)
    }

    /// The participant every tab wants: scrolls this scroll view back to its
    /// `tabTopAnchor()` on a reset.
    ///
    /// Applied to the `ScrollView` itself, because the reader has to sit outside
    /// the scroll view it drives and the anchor inside it. A screen with state
    /// of its own adds `onTabReset(of:)` alongside this rather than instead of
    /// it — the two compose, and neither knows about the other.
    func scrollsToTopOnTabReset(of tab: AppTab) -> some View {
        modifier(ScrollToTopOnTabReset(tab: tab))
    }
}

private enum TabResetAnchor {
    static let top = "tab.reset.top"
}

/// The one place a request becomes an action. Every participant is this.
private struct TabResetResponder: ViewModifier {
    let tab: AppTab
    let action: () -> Void

    @Environment(\.tabResetRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onChange(of: request) { _, new in
            // A request names one tab. Every other tab's participants ignore it,
            // which is what lets a screen answer without knowing whether it is
            // the one on screen.
            guard let new, new.tab == tab else { return }
            // The same easing as the Overview's widget-focus scroll, this app's
            // other programmatic movement — and off under Reduce Motion, where a
            // screen-height slide is exactly what that setting exists to stop.
            // The screen still ends up reset, it just gets there without the
            // travel.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                action()
            }
        }
    }
}

/// Scrolling, expressed as a participant like any other. The `ScrollViewReader`
/// is the only reason this needs a modifier of its own rather than being a
/// closure at a call site.
private struct ScrollToTopOnTabReset: ViewModifier {
    let tab: AppTab

    func body(content: Content) -> some View {
        ScrollViewReader { scroller in
            content.onTabReset(of: tab) {
                scroller.scrollTo(TabResetAnchor.top, anchor: .top)
            }
        }
    }
}
