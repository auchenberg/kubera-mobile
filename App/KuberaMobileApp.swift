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
    /// The last "put this tab back" ask. Published into the environment and
    /// nothing more: what a reset means belongs to the screens, which declare it
    /// themselves — see `TabReset.swift`. This view has no idea what any of them
    /// will do about it.
    @State private var tabReset: TabResetRequest?
    /// The Overview module a widget tap asked for, consumed and cleared by
    /// `OverviewView` once it has scrolled there.
    @State private var overviewFocus: DeepLink.OverviewFocus?

    /// Tapping the tab bar item of the tab you are already on writes the same
    /// value back to the binding, and that write is the only signal iOS gives
    /// for a re-tap. Turning it into a reset request here is what makes the
    /// standard idiom work; a different value is an ordinary switch.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { tapped in
            guard tapped != selection else {
                tabReset = .next(after: tabReset, tab: tapped)
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

            // Two tabs, one screen. Every route into either — a composition row,
            // the ASSETS or DEBTS card, `kubera://assets`, `kubera://debts` —
            // selects the side's tab and hands it the sheet to open on; the
            // screen ignores requests naming the other side.
            ForEach(PortfolioSide.allCases, id: \.self) { side in
                NavigationStack {
                    BookDetailView(
                        side: side,
                        detail: store.detail,
                        currency: (store.snapshot ?? .sample).currency,
                        masked: store.settings.privacyMode,
                        compactNumbers: store.settings.compactNumbers,
                        request: store.bookRequest
                    )
                }
                .tint(Theme.text)
                .tabItem {
                    Label(side.title, systemImage: icon(side.tab))
                }
                .tag(side.tab)
            }

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
        .environment(\.tabResetRequest, tabReset)
        .task {
            // The dashboard shows its own error state for a failed refresh.
            try? await store.refresh()
        }
        // Deep links select a tab: kubera://assets, kubera://debts,
        // kubera://widgets and kubera://settings; anything else — including every widget's
        // plain kubera:// — lands on the dashboard rather than
        // whatever tab was open last.
        // Every route to a book goes through the store, so a widget URL and a tap
        // on the Overview arrive the same way. Selecting the tab here instead
        // would be a second path that could drift from the first.
        .onChange(of: store.bookRequest) { _, request in
            guard let request else { return }
            selection = request.side.tab
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case let .book(side):
                store.showBook(side)
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
        // grid symbol — the Widgets tab further along is already a grid — and
        // deliberately an old symbol, because this pair is guaranteed to
        // resolve in both states.
        case .assets: return selected ? "rectangle.stack.fill" : "rectangle.stack"
        // What you owe, as the thing most of it is borrowed on. Same vintage,
        // same guarantee about the filled variant.
        case .debts: return selected ? "creditcard.fill" : "creditcard"
        case .widgets: return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
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
