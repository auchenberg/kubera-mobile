import SwiftUI
import WidgetKit

@main
struct KuberaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NetWorthStatsWidget()
        CagrWidget()
        AssetsDebtsWidget()
    }
}

/// Shown when the user hasn't connected their Kubera account yet.
struct SignedOutView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Open Kubera Mobile")
        case .accessoryCircular:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
        case .accessoryRectangular:
            Text("Open Kubera Mobile to connect your account")
                .font(.system(size: 12))
        default:
            VStack(spacing: 6) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 20))
                    .foregroundStyle(WidgetTheme.dim)
                Text("Open Kubera Mobile and connect your account")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetTheme.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
