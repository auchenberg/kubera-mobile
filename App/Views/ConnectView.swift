import SwiftUI

/// The one place credentials are entered, used for the first-run connect and
/// for every later edit. Same fields, same validation, same error copy — the
/// only differences are the chrome and which field opens focused.
struct ConnectView: View {
    /// Which credential a row edits. Doubles as the focus target so Settings
    /// can deep-link straight to the field the user tapped Replace on.
    enum Credential: Hashable {
        case apiKey
        case secret
        case mcpToken
    }

    enum Mode: Equatable {
        /// Step 2 of the first run, pushed from `WelcomeView`. No chrome of its
        /// own: the navigation stack supplies the back button.
        case firstRun
        /// Sheet from Settings, with Cancel and an optional focus target.
        case edit(focus: Credential?)

        var isEdit: Bool { self != .firstRun }
    }

    let mode: Mode

    init(mode: Mode = .firstRun) {
        self.mode = mode
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var secret = ""
    @State private var mcpToken = ""
    @State private var revealSecret = false
    @State private var revealToken = false
    /// The user asked to drop a stored token. An empty field can't mean this:
    /// the fields start empty by design and show masked placeholders.
    @State private var removingToken = false
    @State private var busy = false
    /// Validation copy keyed by the field it belongs under, so an error shows
    /// next to the credential that caused it.
    @State private var feedback: [CredentialFeedback.Field: String] = [:]
    @FocusState private var focused: Credential?

    var body: some View {
        Group {
            if mode.isEdit {
                NavigationStack {
                    form
                        .navigationTitle("Kubera credentials")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                                    .foregroundStyle(Theme.text)
                            }
                        }
                }
            } else {
                form
            }
        }
        .onAppear {
            if case let .edit(focus) = mode { focused = focus }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !mode.isEdit { stepHeader }

                Text("Read-only. Nothing is ever written to your Kubera account.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)

                SectionTitle("Balances")
                requiredCard

                SectionTitle("Growth history")
                historyCard

                if let banner = feedback[.banner] {
                    Text(banner)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.negative)
                        .padding(.top, 16)
                }

                ActionButton(
                    title: mode.isEdit ? "Save changes" : "Connect",
                    isLoading: busy,
                    isDisabled: !canSubmit,
                    action: submit
                )
                .padding(.top, 20)

                helpCard
                    .padding(.top, 24)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, mode.isEdit ? 8 : 12)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Step 2's heading. The app's name and promise belong to `WelcomeView`;
    /// this screen only has to say what the three values are for.
    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Provide your keys")
                .font(.system(size: 30, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Theme.text)

            Text(
                """
                The API key and secret fetch your balances. The MCP token fetches \
                growth history. All three are required.
                """
            )
            .font(.system(size: 16))
            .lineSpacing(4)
            .foregroundStyle(Theme.dim)
        }
        .padding(.bottom, 20)
    }

    private var requiredCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CredentialFieldRow(
                    label: "API KEY",
                    placeholder: placeholder(
                        for: store.credentials?.apiKey,
                        fallback: "Paste your Kubera API key"
                    ),
                    text: $apiKey,
                    isSecret: false,
                    reveal: .constant(true),
                    focus: $focused,
                    credential: .apiKey,
                    next: .secret,
                    sanitize: CredentialInput.trimmed
                )

                CredentialFieldRow(
                    label: "API SECRET",
                    placeholder: placeholder(
                        for: store.credentials?.secret,
                        fallback: "Paste your Kubera API secret"
                    ),
                    text: $secret,
                    isSecret: true,
                    reveal: $revealSecret,
                    focus: $focused,
                    credential: .secret,
                    next: .mcpToken,
                    sanitize: CredentialInput.trimmed
                )

                if let message = feedback[.keyAndSecret] {
                    fieldError(message)
                }

                Text("Unlocks: net worth, assets, debts, holdings, allocation.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CredentialFieldRow(
                    label: "MCP TOKEN",
                    placeholder: placeholder(
                        for: store.credentials?.mcpToken,
                        fallback: "Paste your Kubera MCP token"
                    ),
                    text: $mcpToken,
                    isSecret: true,
                    reveal: $revealToken,
                    focus: $focused,
                    credential: .mcpToken,
                    next: nil,
                    sanitize: CredentialInput.sanitizedToken
                )

                if let message = feedback[.mcpToken] {
                    fieldError(message)
                }

                Text(
                    """
                    Required for 1 day, YTD and CAGR. Kubera serves history only \
                    through its MCP endpoint, which needs this token — the API key \
                    cannot fetch it.
                    """
                )
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Theme.dim)

                if store.credentials?.mcpToken != nil, mcpToken.isEmpty {
                    removeTokenRow
                }
            }
        }
    }

    @ViewBuilder
    private var removeTokenRow: some View {
        if removingToken {
            HStack(spacing: 10) {
                Text("Will be removed when you save.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.negative)
                Button("Keep it") { removingToken = false }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        } else {
            Button("Remove stored token") { removingToken = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.negative)
        }
    }

    private var helpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where do I find these?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(
                    """
                    In Kubera on the web, "Create New API Key" gives you the first two \
                    fields — the secret is only shown once. "Create MCP Token" on the same \
                    page gives you the third. Everything is stored only on this device.
                    """
                )
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.dim)

                Link(destination: Self.apiSettingsURL) {
                    HStack(spacing: 6) {
                        Text("Open Kubera API settings")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                }
                .padding(.top, 4)
            }
        }
    }

    /// Deep link straight to the API tab of Kubera's account settings, so the
    /// three values are one tap away rather than four menus deep.
    static let apiSettingsURL = URL(
        string: "https://app.kubera.com/networth#modal=account_settings&tab=api_access"
    )!

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(Theme.negative)
    }

    /// Editing never prefills a secret. A stored credential shows as a mask, so
    /// an empty field always means "leave this one alone".
    private func placeholder(for stored: String?, fallback: String) -> String {
        guard let stored, !stored.isEmpty else { return fallback }
        return CredentialMask.secret(stored)
    }

    // MARK: - Submit

    private var apiKeyEdit: CredentialEdit { apiKey.isEmpty ? .unchanged : .set(apiKey) }
    private var secretEdit: CredentialEdit { secret.isEmpty ? .unchanged : .set(secret) }
    private var tokenEdit: CredentialEdit {
        if !mcpToken.isEmpty { return .set(mcpToken) }
        return removingToken ? .cleared : .unchanged
    }

    private var canSubmit: Bool {
        if store.credentials == nil {
            // All three are required: the key pair fetches balances, and the
            // MCP token is the only way to fetch history at all.
            return !apiKey.isEmpty && !secret.isEmpty && !mcpToken.isEmpty
        }
        return apiKeyEdit != .unchanged || secretEdit != .unchanged || tokenEdit != .unchanged
    }

    private func submit() {
        busy = true
        feedback = [:]
        Task {
            do {
                let tokenProblem = try await store.updateCredentials(
                    apiKey: apiKeyEdit,
                    secret: secretEdit,
                    mcpToken: tokenEdit
                )
                if let tokenProblem, tokenEdit != .unchanged {
                    // Key and secret are saved; only the token was
                    // rejected, so stay open with the reason on its field.
                    feedback[tokenProblem.field] = tokenProblem.text
                    feedback[.banner] = """
                    Your key and secret were saved, but growth history won't work until the \
                    token does — until then it falls back to the on-device log.
                    """
                } else if mode.isEdit {
                    dismiss()
                }
            } catch let error as AppStore.CredentialError {
                feedback[error.feedback.field] = error.feedback.text
            } catch {
                feedback[.banner] = error.localizedDescription
            }
            busy = false
        }
    }
}

/// One labelled credential row: field plus a reveal toggle for secrets.
private struct CredentialFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let isSecret: Bool
    @Binding var reveal: Bool
    @FocusState.Binding var focus: ConnectView.Credential?
    let credential: ConnectView.Credential
    /// Where the keyboard's Next key goes; nil makes it a Done key.
    let next: ConnectView.Credential?
    let sanitize: (String) -> String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .kerning(1)
                .foregroundStyle(Theme.dim)

            HStack(spacing: 8) {
                input
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // Offers the Passwords keychain on the secrets instead of
                    // autocorrect suggestions.
                    .textContentType(isSecret ? .password : nil)
                    .submitLabel(next == nil ? .done : .next)
                    .focused($focus, equals: credential)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .onSubmit { focus = next }
                    // Paste and autofill can both deliver decorated values, so
                    // clean as we go — the user sees what will be stored.
                    .onChange(of: text) { _, newValue in
                        let cleaned = sanitize(newValue)
                        if cleaned != newValue { text = cleaned }
                    }

                if isSecret, !text.isEmpty {
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.dim)
                    }
                    .accessibilityLabel(reveal ? "Hide \(label)" : "Show \(label)")
                }

            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1 / displayScale)
            )
        }
    }

    @ViewBuilder
    private var input: some View {
        if isSecret, !reveal {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

#Preview("First run — step 2") {
    ConnectView(mode: .firstRun)
        .environment(AppStore())
}

#Preview("Editing") {
    ConnectView(mode: .edit(focus: .mcpToken))
        .environment(AppStore())
}
