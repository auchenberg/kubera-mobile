import SwiftUI

/// First-run flow, in two steps: what the app does (`WelcomeView`), then the
/// credentials (`ConnectView`, the same screen Settings presents for later
/// edits — one set of fields, one validation path).
///
/// There is no third step. A successful connect makes `AppStore.credentials`
/// non-nil, and the root view swaps this whole flow for the main tabs; landing
/// in the app is the confirmation.
struct SignInView: View {
    /// A `NavigationStack` path rather than a transition, so the swipe-back
    /// gesture works on step 2 without reimplementing it.
    private enum Step: Hashable {
        case connect
    }

    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.connect) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .connect:
                        ConnectView(mode: .firstRun)
                            // An empty inline bar: all the chrome we want here
                            // is the back button, since the step's own heading
                            // scrolls with the fields.
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(Theme.background, for: .navigationBar)
                    }
                }
        }
        .tint(Theme.text)
    }
}

#Preview("First run") {
    SignInView()
        .environment(AppStore())
}
