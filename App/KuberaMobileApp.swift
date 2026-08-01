import SwiftUI

@main
struct KuberaMobileApp: App {
    @State private var store = AppStore()
    @State private var appLock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _appLock = State(initialValue: AppLock(enabled: store.settings.appLockEnabled))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(appLock)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.noteBackgrounded()
            case .active:
                appLock.noteForegrounded(enabled: store.settings.appLockEnabled)
            default:
                break
            }
        }
    }
}

private struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLock.self) private var appLock

    /// Nothing to protect until an account is connected, so onboarding is never
    /// gated — a first run would otherwise open on a Face ID prompt guarding an
    /// empty app.
    private var shouldLock: Bool {
        store.credentials != nil && store.settings.appLockEnabled && appLock.isLocked
    }

    var body: some View {
        ZStack {
            if store.credentials == nil {
                SignInView()
            } else {
                MainTabView()
            }

            if shouldLock {
                LockScreenView()
            }
        }
    }
}

/// Opaque cover while locked — nothing underneath may show through.
private struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.dim)
            Text("Kubera Mobile")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            ActionButton(title: "Unlock with Face ID") {
                Task { await appLock.unlock() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .task {
            // Prompt as soon as the cover appears, so a normal launch is
            // one Face ID glance with no tap needed.
            await appLock.unlock()
        }
    }
}

private struct MainTabView: View {
    /// Always the Overview, except in a debug run that asked for another tab.
    /// Opening straight onto a tab exists so screenshots can be taken without
    /// driving the UI: `simctl openurl` raises a system "Open in…" confirmation
    /// that `simctl` has no way to dismiss.
    ///
    ///     xcrun simctl launch <device> com.kubera.mobile \
    ///       -KuberaDemoMode -KuberaInitialTab widgets
    ///
    /// The mapping itself is `AppTab.initial(fromLaunchArgument:)`, which is
    /// tested; this only reads the argument.
    private static var initialTab: AppTab {
        #if DEBUG
        return AppTab.initial(fromLaunchArgument: UserDefaults.standard.string(forKey: "KuberaInitialTab"))
        #else
        return .overview
        #endif
    }

    @Environment(AppStore.self) private var store
    @State private var selection: AppTab = MainTabView.initialTab
    /// The last "scroll back to the top" ask, handed down the environment so a
    /// tab root can answer it without every screen taking a parameter it would
    /// only pass through.
    @State private var scrollToTop: ScrollToTopRequest?
    /// The Overview module a widget tap asked for, consumed and cleared by
    /// `OverviewView` once it has scrolled there.
    @State private var overviewFocus: DeepLink.OverviewFocus?

    /// Tapping the tab bar item of the tab you are already on writes the same
    /// value back to the binding, and that write is the only signal iOS gives
    /// for a re-tap. Turning it into a scroll request here is what makes the
    /// standard idiom work; a different value is an ordinary switch.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { tapped in
            guard tapped != selection else {
                scrollToTop = .next(after: scrollToTop, tab: tapped)
                return
            }
            selection = tapped
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            OverviewView(focus: $overviewFocus)
                .tabItem {
                    Label("Overview", systemImage: icon(.overview))
                }
                .tag(AppTab.overview)

            // The only assets screen in the app. The Overview used to push a
            // second copy into its own stack, which is what left the tab bar
            // pointing at Overview while assets were on screen; now every route
            // to assets — a row, the ASSETS card, `kubera://assets` — selects
            // this tab and hands it the sheet to open on.
            NavigationStack {
                AssetDetailView(
                    detail: store.detail,
                    currency: (store.snapshot ?? .sample).currency,
                    masked: store.settings.privacyMode,
                    compactNumbers: store.settings.compactNumbers,
                    request: store.assetsRequest
                )
            }
            .tint(Theme.text)
            .tabItem {
                Label("Assets", systemImage: icon(.assets))
            }
            .tag(AppTab.assets)

            WidgetsView()
                .tabItem {
                    Label("Widgets", systemImage: icon(.widgets))
                }
                .tag(AppTab.widgets)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: icon(.settings))
                }
                .tag(AppTab.settings)
        }
        .modifier(MinimizingTabBar())
        .environment(\.scrollToTopRequest, scrollToTop)
        .task {
            // The dashboard shows its own error state for a failed refresh.
            try? await store.refresh()
        }
        // Deep links select a tab: kubera://assets, kubera://widgets and
        // kubera://settings; anything else — including every widget's
        // plain kubera:// — lands on the dashboard rather than
        // whatever tab was open last.
        // Every route to the assets tab goes through the store, so a widget URL
        // and a tap on the Overview arrive the same way. Selecting the tab here
        // instead would be a second path that could drift from the first.
        .onChange(of: store.assetsRequest) { _, request in
            guard request != nil else { return }
            selection = .assets
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case .assets:
                store.showAssets()
            case .widgets:
                selection = .widgets
            case .settings:
                selection = .settings
            case let .overview(focus):
                selection = .overview
                // Carries the module a widget was showing, so the Overview can
                // bring it into view. Re-set even when it matches the previous
                // value so tapping the same widget twice scrolls again.
                overviewFocus = nil
                overviewFocus = focus
            }
        }
    }

    /// Explicit pairs rather than appending ".fill": not every symbol has a
    /// filled variant, and a name that doesn't resolve renders as nothing —
    /// which is how the Overview tab lost its icon when selected.
    private func icon(_ tab: AppTab) -> String {
        let selected = selection == tab
        switch tab {
        case .overview: return "chart.line.uptrend.xyaxis"
        // A stack of sheets, which is what the screen is. Deliberately not a
        // grid symbol — the Widgets tab next to it is already a grid — and
        // deliberately an old symbol, because this pair is guaranteed to
        // resolve in both states.
        case .assets: return selected ? "rectangle.stack.fill" : "rectangle.stack"
        case .widgets: return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }
}

// MARK: - Scroll to top

extension EnvironmentValues {
    /// The most recent ask to scroll a tab back to the top. Nil in previews and
    /// anywhere outside the tab bar, where a screen simply never scrolls itself.
    var scrollToTopRequest: ScrollToTopRequest? {
        get { self[ScrollToTopRequestKey.self] }
        set { self[ScrollToTopRequestKey.self] = newValue }
    }
}

private struct ScrollToTopRequestKey: EnvironmentKey {
    static let defaultValue: ScrollToTopRequest? = nil
}

extension View {
    /// Marks this view as the top of its tab's scrolling content — the thing a
    /// re-tap of the tab bar item scrolls back to. One per scroll view.
    func scrollTopAnchor() -> some View {
        id(ScrollAnchor.top)
    }

    /// Scrolls this scroll view back to its `scrollTopAnchor()` when `tab`'s tab
    /// bar item is tapped while that tab is already showing.
    ///
    /// Applied to the `ScrollView` itself: the reader has to sit outside the
    /// scroll view it drives, and the anchor inside it, so wrapping here is what
    /// keeps both true without every screen growing a `ScrollViewReader` of its
    /// own.
    func scrollsToTopOnReselect(of tab: AppTab) -> some View {
        modifier(ScrollToTopModifier(tab: tab))
    }
}

private enum ScrollAnchor {
    static let top = "scroll.top"
}

private struct ScrollToTopModifier: ViewModifier {
    let tab: AppTab

    @Environment(\.scrollToTopRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { scroller in
            content.onChange(of: request) { _, new in
                guard let new, new.tab == tab else { return }
                // The same easing as the Overview's widget-focus scroll, which
                // is this app's other programmatic jump — and off under Reduce
                // Motion, where a screen-height slide is exactly the movement
                // that setting exists to stop. The content still arrives at the
                // top, it just gets there without the travel.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                    scroller.scrollTo(ScrollAnchor.top, anchor: .top)
                }
            }
        }
    }
}

/// Lets the floating tab bar shrink out of the way as content scrolls up, which
/// is what iOS 26 apps do and what the screens' own bottom padding now assumes.
/// Reported not to fire in tabs built on `NavigationStack(path:)`; the Overview's
/// stack has no path binding, so it should — but confirm on a device before
/// trusting it, because failure here is silent.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
