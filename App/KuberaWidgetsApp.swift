import SwiftUI

@main
struct KuberaWidgetsApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

private struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.credentials == nil {
            SignInView()
        } else {
            MainTabView()
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
            DashboardView()
                .tabItem {
                    Label("Net Worth", systemImage: symbol("chart.pie", for: .dashboard))
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
