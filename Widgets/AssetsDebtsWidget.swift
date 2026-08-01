import SwiftUI
import WidgetKit

struct AssetsDebtsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AssetsDebtsWidget", provider: KuberaProvider()) { entry in
            AssetsDebtsView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Assets vs Debts")
        .description("How your assets stack up against your debts.")
        .supportedFamilies([.systemMedium])
    }
}

struct AssetsDebtsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KuberaEntry

    var body: some View {
        switch entry.state {
        case .signedOut:
            SignedOutView(family: family)
        case .data(let snapshot):
            AssetsDebtsWidgetContent(
                snapshot: snapshot,
                settings: entry.settings,
                family: family
            )
            // The one widget that itemizes rather than summarizes: it shows the
            // asset side split up, so it opens the screen that lists the split.
            // NetWorthStats and Cagr stay on their Overview foci — their figures
            // live there and nowhere else.
            .widgetURL(DeepLink.assets.url)
        }
    }
}
