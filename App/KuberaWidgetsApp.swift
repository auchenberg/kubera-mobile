import SwiftUI

@main
struct KuberaWidgetsApp: App {
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

    var body: some View {
        ZStack {
            if store.credentials == nil {
                SignInView()
            } else {
                MainTabView()
            }

            if appLock.isLocked && store.settings.appLockEnabled {
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
        case dashboard, widgets, settings
    }

    @Environment(AppStore.self) private var store
    @State private var selection: Tab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            OverviewView()
                .tabItem {
                    Label("Overview", systemImage: symbol("chart.line.uptrend.xyaxis", for: .dashboard))
                }
                .tag(Tab.dashboard)

            WidgetsView()
                .tabItem {
                    Label("Widgets", systemImage: symbol("square.grid.2x2", for: .widgets))
                }
                .tag(Tab.widgets)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: symbol("gearshape", for: .settings))
                }
                .tag(Tab.settings)
        }
        .task {
            // The dashboard shows its own error state for a failed refresh.
            try? await store.refresh()
        }
        // Deep links select a tab: kuberawidgets://widgets and
        // kuberawidgets://settings; anything else — including every widget's
        // plain kuberawidgets:// — lands on the dashboard rather than
        // whatever tab was open last.
        .onOpenURL { url in
            switch url.host() {
            case "widgets": selection = .widgets
            case "settings": selection = .settings
            default: selection = .dashboard
            }
        }
    }

    private func symbol(_ name: String, for tab: Tab) -> String {
        selection == tab ? "\(name).fill" : name
    }
}
