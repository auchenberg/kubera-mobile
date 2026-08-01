import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppLock.self) private var appLock
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var confirmingDisconnect = false
    @State private var checking = false

    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 44

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader("Settings")
                        .scrollTopAnchor()
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    IdentityHeader(
                        profile: store.profile,
                        portfolioLine: portfolioLine,
                        connection: store.connection,
                        credentials: store.credentials,
                        isChecking: checking,
                        onCheck: checkConnection
                    )

                    disconnectRow
                        .padding(.top, 12)

                    if !store.portfolios.isEmpty {
                        SectionTitle("Widget portfolio")
                        portfolioCard
                    }

                    SectionTitle("Preferences")
                    preferencesCard

                    SectionTitle("Data & privacy")
                    privacyFooter
                }
                .padding(.horizontal, 20)
                .safeAreaPadding(.bottom)
            }
            .background(Theme.background)
            .softTopScrollEdge()
            // No nav title: `ScreenHeader` is this screen's heading, matching
            // Overview. A large-title bar would reserve its own space above the
            // scroll and push the first card down past where Overview's sits.
            .toolbar(.hidden, for: .navigationBar)
            .scrollsToTopOnReselect(of: .settings)
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
                    with the cached balances and the on-device history log. Widgets stop \
                    updating until you connect again. This is also how you change \
                    credentials: disconnect, then reconnect with the new ones.
                    """
                )
            }
        }
    }

    /// Ends the connection the header describes, so it sits with the identity
    /// rather than further down the scroll.
    ///
    /// A row rather than a filled red button: iOS puts Sign Out in a plain row
    /// in its own account sheets, and a full-width red slab here outshouted the
    /// net worth it is meant to sit beneath. The confirmation dialog is what
    /// makes this safe, not the loudness of the control.
    private var disconnectRow: some View {
        Card(padding: .cardRows) {
            Button {
                confirmingDisconnect = true
            } label: {
                Text("Disconnect Kubera")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.negative)
                    .frame(maxWidth: .infinity, minHeight: rowMinHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func checkConnection() {
        checking = true
        Task {
            await store.checkConnection()
            checking = false
        }
    }

    /// The portfolio the widgets read, which is what the header identifies. The
    /// cached snapshot answers before the portfolio list has loaded.
    private var portfolioLine: String? {
        if let selected = store.portfolios.first(where: { $0.id == store.selectedPortfolioId }) {
            return "\(selected.name) · \(selected.currency)"
        }
        if let snapshot = store.snapshot {
            return "\(snapshot.portfolioName) · \(snapshot.currency)"
        }
        return nil
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
        let isSelected = portfolio.id == store.selectedPortfolioId

        return SplitRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(portfolio.name)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                Text(portfolio.currency)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        } trailing: {
            if isSelected {
                Text("On widgets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: rowMinHeight)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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

    /// A two-line toggle label is unreadable next to a switch at accessibility
    /// sizes, so the description drops below the control and becomes a hint.
    @ViewBuilder
    private func preferenceRow(
        _ label: String,
        description: String,
        value: Bool,
        onToggle: ((Bool) -> Void)? = nil,
        apply: @escaping (inout WidgetSettings, Bool) -> Void
    ) -> some View {
        let binding = Binding(
            get: { value },
            set: { newValue in
                store.updateSettings { apply(&$0, newValue) }
                onToggle?(newValue)
            }
        )

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: binding) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                }
                .accessibilityHint(description)

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: rowMinHeight)
            .padding(.vertical, 10)
        } else {
            Toggle(isOn: binding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
            }
            .frame(minHeight: rowMinHeight)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Data & privacy

    private var privacyFooter: some View {
        Text(
            """
            Your API key is stored in the iOS Keychain, in an access group shared only \
            with the widget extension. Portfolio data is cached on-device for the widgets. \
            The app talks directly to api.kubera.com — there is no middleman server. \
            All requests are read-only.
            """
        )
        .font(.footnote)
        .lineSpacing(3)
        .foregroundStyle(Theme.dim)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Identity header

/// Who this account is, and the health of the connection it names. Takes plain
/// values rather than the store so it renders in previews without one.
private struct IdentityHeader: View {
    let profile: KuberaProfile?
    let portfolioLine: String?
    let connection: ConnectionStatus
    let credentials: KuberaCredentials?
    let isChecking: Bool
    let onCheck: () -> Void

    @Environment(\.displayScale) private var displayScale

    @ScaledMetric(relativeTo: .title2) private var monogramSize: CGFloat = 66

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                identity

                RowDivider()
                    .padding(.vertical, 14)

                status

                RowDivider()
                    .padding(.vertical, 14)

                CredentialRow(
                    label: "API key",
                    mask: credentials.map { CredentialMask.key($0.apiKey) } ?? "Not set",
                    presence: restPresence
                )

                RowDivider()

                CredentialRow(
                    label: "API secret",
                    mask: CredentialMask.secret(credentials?.secret),
                    presence: restPresence
                )

                RowDivider()

                CredentialRow(
                    label: "MCP token",
                    mask: CredentialMask.secret(credentials?.mcpToken),
                    presence: mcpTokenPresence,
                    note: mcpTokenNote
                )
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Text(Monogram.initials(name: profile?.name, email: profile?.email))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: monogramSize, height: monogramSize)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .overlay(
                    Circle().strokeBorder(Theme.border, lineWidth: 1 / displayScale)
                )
                .accessibilityHidden(true)
                .padding(.bottom, 4)

            Text(displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)

            if let portfolioLine {
                Text(portfolioLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
        .multilineTextAlignment(.center)
        // Both lines wrap rather than truncate. A name and a portfolio are the
        // two things on this screen the user cannot infer from context, so
        // "Sample portfoli…" at an accessibility size is worse than two lines.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// Balances and growth history fail independently, so each reports its own
    /// last real outcome.
    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            SplitRow {
                Text(connection.headline)
                    .font(.headline)
                    .foregroundStyle(connection.headlineRole.color)
            } trailing: {
                checkButton
            }

            statusLine(connection.restLine())
            statusLine(connection.historyLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checkButton: some View {
        Button(action: onCheck) {
            if isChecking {
                ProgressView().controlSize(.small)
            } else {
                Text("Check now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .disabled(isChecking || credentials == nil)
    }

    private func statusLine(_ line: ConnectionStatus.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(line.surface)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(line.state)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(line.role.color)
            }
            .accessibilityElement(children: .combine)

            if let detail = line.detail {
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restPresence: CredentialRow.Presence {
        if credentials == nil { return .missing }
        return connection.rest == .authFailed ? .rejected : .present
    }

    private var mcpTokenPresence: CredentialRow.Presence {
        if credentials?.mcpToken == nil { return .missing }
        if case .failed = connection.history { return .rejected }
        return .present
    }

    /// Says what this credential buys, because it is the one row on the screen
    /// whose absence changes the numbers rather than breaking them: the 1 day,
    /// YTD and CAGR figures silently become a local estimate. Stated in every
    /// state — a rejection's own reason is already on the History line above.
    private var mcpTokenNote: String {
        """
        Serves the real 1 day, YTD and CAGR figures. Without one, growth is \
        estimated from the log this device keeps.
        """
    }

    private var displayName: String {
        Monogram.displayName(name: profile?.name, email: profile?.email)
    }
}

// MARK: - Rows

/// A stored credential shown as evidence that it exists: a status glyph and a
/// short mask, never a value.
private struct CredentialRow: View {
    enum Presence {
        case present
        case missing
        case rejected
    }

    let label: String
    let mask: String
    let presence: Presence
    var note: String? = nil

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SplitRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(role.color)
                        .frame(width: glyphWidth, alignment: .leading)

                    Text(label)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                }
            } trailing: {
                Text(mask)
                    .font(maskFont)
                    .foregroundStyle(Theme.dim)
            }

            if let note {
                Text(note)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: rowMinHeight)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch presence {
        case .present: "checkmark.circle.fill"
        case .missing: "circle.dashed"
        case .rejected: "exclamationmark.triangle.fill"
        }
    }

    private var role: ConnectionStatus.Role {
        switch presence {
        case .present: .positive
        case .missing: .dim
        case .rejected: .negative
        }
    }

    private var maskFont: Font {
        presence == .missing ? .footnote : .system(.footnote, design: .monospaced)
    }
}

/// Label-left, value-right — stacked at accessibility sizes, where the two
/// halves cannot share a line without crushing one of them.
private struct SplitRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                leading()
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
        }
    }
}

private extension ConnectionStatus.Role {
    var color: Color {
        switch self {
        case .positive: Theme.positive
        case .negative: Theme.negative
        case .dim: Theme.dim
        }
    }
}

#if DEBUG
/// Synthetic throughout: this repo is public, and a preview must never carry a
/// real credential or a real balance.
private let previewCredentials = KuberaCredentials(
    apiKey: "kbra_pk_EXAMPLE_0001",
    secret: "EXAMPLE_SECRET",
    mcpToken: "EXAMPLE_MCP_TOKEN"
)

#Preview("Settings") {
    SettingsView()
        .environment(AppStore())
        .environment(AppLock(enabled: false))
}

#Preview("Settings — AX5") {
    SettingsView()
        .environment(AppStore())
        .environment(AppLock(enabled: false))
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Header — connected") {
    ScrollView {
        IdentityHeader(
            profile: DemoData.profile,
            portfolioLine: "\(DemoData.portfolios[0].name) · \(DemoData.portfolios[0].currency)",
            connection: ConnectionStatus(
                rest: .connected(at: Date().addingTimeInterval(-240)),
                history: .connected(points: 182)
            ),
            credentials: previewCredentials,
            isChecking: false,
            onCheck: {}
        )
        .padding(.horizontal, 20)
    }
    .background(Theme.background)
}

/// The contrast key reaches `Card` and `RowDivider`, which read
/// `\.colorSchemeContrast` and thicken their hairlines. It does **not** reach
/// `Theme`'s colours: those resolve through UIKit traits, so only the real
/// system setting changes them. A preview that looks unchanged is not a bug.
#Preview("Header — needs attention, AX5 + increased contrast") {
    ScrollView {
        IdentityHeader(
            profile: KuberaProfile(name: nil, email: nil),
            portfolioLine: nil,
            connection: ConnectionStatus(
                rest: .authFailed,
                history: .failed("Kubera rejected this MCP token.")
            ),
            credentials: previewCredentials,
            isChecking: false,
            onCheck: {}
        )
        .padding(.horizontal, 20)
    }
    .background(Theme.background)
    .environment(\.dynamicTypeSize, .accessibility5)
    .environment(\._colorSchemeContrast, .increased)
    .environment(\._accessibilityDifferentiateWithoutColor, true)
}
#endif
