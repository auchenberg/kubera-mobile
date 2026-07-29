import SwiftUI

/// First-run screen. Credential entry lives entirely in `ConnectView`, which
/// Settings presents again for later edits — one screen, one validation path.
struct SignInView: View {
    var body: some View {
        ConnectView(mode: .firstRun)
    }
}
