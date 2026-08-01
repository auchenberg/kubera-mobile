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
    private enum Tab {
        case dashboard, assets, widgets, settings

        /// Always the dashboard, except in a debug run that asked for another
        /// tab. Opening straight onto a tab exists so screenshots can be taken
        /// without driving the UI: `simctl openurl` raises a system "Open in…"
        /// confirmation that `simctl` has no way to dismiss.
        ///
        ///     xcrun simctl launch <device> com.kubera.mobile \
        ///       -KuberaDemoMode -KuberaInitialTab widgets
        static var initial: Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "KuberaInitialTab") {
            case "assets": return .assets
            case "widgets": return .widgets
            case "settings": return .settings
            default: return .dashboard
            }
            #else
            return .dashboard
            #endif
        }
    }

    @Environment(AppStore.self) private var store
    @State private var selection: Tab = Tab.initial
    /// The Overview module a widget tap asked for, consumed and cleared by
    /// `OverviewView` once it has scrolled there.
    @State private var overviewFocus: DeepLink.OverviewFocus?

    var body: some View {
        TabView(selection: $selection) {
            OverviewView(focus: $overviewFocus)
                .tabItem {
                    Label("Overview", systemImage: icon(.dashboard))
                }
                .tag(Tab.dashboard)

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
            .tag(Tab.assets)

            WidgetsView()
                .tabItem {
                    Label("Widgets", systemImage: icon(.widgets))
                }
                .tag(Tab.widgets)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: icon(.settings))
                }
                .tag(Tab.settings)
        }
        .modifier(MinimizingTabBar())
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
                selection = .dashboard
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
    private func icon(_ tab: Tab) -> String {
        let selected = selection == tab
        switch tab {
        case .dashboard: return "chart.line.uptrend.xyaxis"
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
