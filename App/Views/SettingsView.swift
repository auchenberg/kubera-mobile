import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLock.self) private var appLock
    @State private var confirmingDisconnect = false
    @State private var editRequest: EditRequest?
    @State private var checking = false

    /// A pending presentation of `ConnectView`, carrying which field it should
    /// open focused. Wrapped in a type with an id so each tap presents afresh.
    private struct EditRequest: Identifiable {
        let id = UUID()
        let focus: ConnectView.Credential?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Kubera account")
                    accountCard

                    if !store.portfolios.isEmpty {
                        SectionTitle("Widget portfolio")
                        portfolioCard
                    }

                    SectionTitle("Preferences")
                    preferencesCard

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
            .sheet(item: $editRequest) { request in
                ConnectView(mode: .edit(focus: request.focus))
            }
            .confirmationDialog(
                "Disconnect Kubera?",
                isPresented: $confirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { store.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    """
                    This removes your API key, secret and MCP token from this device, along \
                    with the cached balances and the on-device history log that growth \
                    numbers are built from. Widgets stop updating. To change a key without \
                    losing any of that, use Update credentials instead.
                    """
                )
            }
        }
    }

    // MARK: - Kubera account

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                statusHeader

                RowDivider()
                    .padding(.vertical, 14)

                credentialRow(
                    label: "API key",
                    value: store.credentials.map { CredentialMask.key($0.apiKey) } ?? "Not set",
                    isSet: store.credentials != nil,
                    focus: .apiKey
                )

                RowDivider()
                credentialRow(
                    label: "API secret",
                    value: CredentialMask.secret(store.credentials?.secret),
                    isSet: store.credentials != nil,
                    focus: .secret
                )

                RowDivider()
                credentialRow(
                    label: "MCP token",
                    value: CredentialMask.secret(store.credentials?.mcpToken),
                    isSet: store.credentials?.mcpToken != nil,
                    note: store.credentials?.mcpToken == nil ? "Required for growth history" : nil,
                    focus: .mcpToken
                )

                ActionButton(title: "Update credentials") {
                    editRequest = EditRequest(focus: nil)
                }
                .padding(.top, 18)
            }
        }
    }

    /// The two lines that matter: balances and growth history fail
    /// independently, so each reports its own last real outcome.
    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.connection.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color(for: store.connection.headlineRole))

                Spacer(minLength: 12)

                Button {
                    checking = true
                    Task {
                        await store.checkConnection()
                        checking = false
                    }
                } label: {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check now")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
                .disabled(checking || store.credentials == nil)
            }

            statusLine(store.connection.restLine())
            statusLine(store.connection.historyLine)
        }
    }

    private func statusLine(_ line: ConnectionStatus.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(line.surface.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(line.state)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color(for: line.role))
            }

            if let detail = line.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func credentialRow(
        label: String,
        value: String,
        isSet: Bool,
        note: String? = nil,
        focus: ConnectView.Credential
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)

                Text(value)
                    .font(.system(size: 13, design: isSet ? .monospaced : .default))
                    .foregroundStyle(Theme.dim)

                if let note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer(minLength: 12)

            Button(isSet ? "Replace" : "Add") {
                editRequest = EditRequest(focus: focus)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 12)
    }

    private func color(for role: ConnectionStatus.Role) -> Color {
        switch role {
        case .positive: Theme.positive
        case .negative: Theme.negative
        case .dim: Theme.dim
        }
    }

    // MARK: - Widget portfolio

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

    // MARK: - Preferences

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

    // MARK: - Data & privacy

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
}
