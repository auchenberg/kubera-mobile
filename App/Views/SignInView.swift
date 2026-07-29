import SwiftUI

struct SignInView: View {
    @Environment(AppStore.self) private var store

    @State private var apiKey = ""
    @State private var secret = ""
    @State private var mcpToken = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Kubera Mobile")
                    .font(.system(size: 32, weight: .bold))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.text)

                Text("Your net worth, on your Home Screen.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 6)
                    .padding(.bottom, 32)

                credentialsCard
                    .padding(.bottom, 16)

                helpCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
    }

    private var credentialsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("API KEY")
                TextField("Paste your Kubera API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())

                fieldLabel("API SECRET")
                    .padding(.top, 16)
                SecureField("Paste your Kubera API secret", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())

                fieldLabel("MCP TOKEN · OPTIONAL")
                    .padding(.top, 16)
                SecureField("Enables growth history (1 day, YTD, CAGR)", text: $mcpToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .modifier(FieldStyle())

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.negative)
                        .padding(.top, 12)
                }

                ActionButton(
                    title: "Connect to Kubera",
                    isLoading: busy,
                    isDisabled: !canSubmit,
                    action: connect
                )
                .padding(.top, 20)
            }
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
                    Open Kubera on the web, go to Settings → API, and create an API key. \
                    Copy the key and secret here. The MCP Token from the same page is \
                    optional — it unlocks growth history for the widgets. Keys are stored \
                    only on this device and are used to read your portfolio — nothing is \
                    ever written to your Kubera account.
                    """
                )
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.dim)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .kerning(1)
            .foregroundStyle(Theme.dim)
            .padding(.bottom, 6)
    }

    private func connect() {
        busy = true
        errorMessage = nil
        Task {
            do {
                try await store.signIn(apiKey: apiKey, secret: secret, mcpToken: mcpToken)
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}

private struct FieldStyle: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1 / displayScale)
            )
    }
}
