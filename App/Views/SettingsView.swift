import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLock.self) private var appLock
    @State private var confirmingDisconnect = false
    @State private var mcpToken = ""
    @State private var savingToken = false
    @State private var tokenStatus: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Account")
                    accountCard

                    if !store.portfolios.isEmpty {
                        SectionTitle("Widget portfolio")
                        portfolioCard
                    }

                    SectionTitle("Preferences")
                    preferencesCard

                    SectionTitle("Growth history")
                    mcpTokenCard

                    SectionTitle("Data & privacy")
                    privacyCard

                    ActionButton(title: "Disconnect Kubera", kind: .destructive) {
                        confirmingDisconnect = true
                    }
                    .padding(.top, 28)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Disconnect Kubera?",
                isPresented: $confirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { store.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your API key will be removed from this device and widgets will stop updating.")
            }
        }
    }

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connected with API key")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)

                Text(store.credentials.map { maskKey($0.apiKey) } ?? "Not connected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private var portfolioCard: some View {
        Card(padding: .cardRows) {
            VStack(spacing: 0) {
                ForEach(Array(store.portfolios.enumerated()), id: \.element.id) { index, portfolio in
                    if index > 0 { RowDivider() }
                    Button {
                        Task { await store.selectPortfolio(portfolio.id) }
                    } label: {
                        portfolioRow(portfolio)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func portfolioRow(_ portfolio: PortfolioListItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(portfolio.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                Text(portfolio.currency)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 12)

            if portfolio.id == store.selectedPortfolioId {
                Text("On widgets")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
    }

    private var preferencesCard: some View {
        Card(padding: .cardRows) {
            VStack(spacing: 0) {
                preferenceRow(
                    "Require Face ID",
                    description: "Lock the app when you leave it",
                    value: store.settings.appLockEnabled,
                    onToggle: { appLock.setEnabled($0) }
                ) { settings, enabled in
                    settings.appLockEnabled = enabled
                }

                RowDivider()
                preferenceRow(
                    "Privacy mode",
                    description: "Mask all amounts on the Home Screen",
                    value: store.settings.privacyMode
                ) { settings, enabled in
                    settings.privacyMode = enabled
                }

                RowDivider()
                preferenceRow(
                    "Compact numbers",
                    description: "Show $1.24M instead of $1,240,000",
                    value: store.settings.compactNumbers
                ) { settings, enabled in
                    settings.compactNumbers = enabled
                }
            }
        }
    }

    private func preferenceRow(
        _ label: String,
        description: String,
        value: Bool,
        onToggle: ((Bool) -> Void)? = nil,
        apply: @escaping (inout WidgetSettings, Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                store.updateSettings { apply(&$0, newValue) }
                onToggle?(newValue)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 12)
    }

    private var mcpTokenCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if store.credentials?.mcpToken != nil {
                    Text("MCP token connected — growth numbers (1 day, YTD, CAGR) come from Kubera's history API.")
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.positive)
                } else {
                    Text(
                        """
                        Growth numbers (1 day, YTD, CAGR) need Kubera's history API, which \
                        uses its own token. Create an MCP Token in Kubera web → Settings → \
                        API and paste it here.
                        """
                    )
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.dim)
                }

                SecureField("Paste your Kubera MCP token", text: $mcpToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )

                ActionButton(
                    title: "Save token",
                    isLoading: savingToken,
                    isDisabled: mcpToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    savingToken = true
                    tokenStatus = nil
                    Task {
                        await store.saveMCPToken(mcpToken)
                        savingToken = false
                        mcpToken = ""
                        tokenStatus = SharedStore.cachedTrends()?.ytd != nil
                            ? "Connected — growth numbers are live."
                            : "Saved. If growth numbers stay empty, double-check the token."
                    }
                }

                if let tokenStatus {
                    Text(tokenStatus)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                }

                if let fetchStatus = SharedStore.historyStatus() {
                    Text(fetchStatus)
                        .font(.system(size: 13))
                        .foregroundStyle(fetchStatus.hasPrefix("History:") ? Theme.positive : Theme.negative)
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            Text(
                """
                Your API key is stored in the iOS Keychain, in an access group shared only \
                with the widget extension. Portfolio data is cached on-device for the widgets. \
                The app talks directly to api.kubera.com — there is no middleman server. \
                All requests are read-only.
                """
            )
            .font(.system(size: 14))
            .lineSpacing(4)
            .foregroundStyle(Theme.dim)
        }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(4))••••\(key.suffix(4))"
    }
}
