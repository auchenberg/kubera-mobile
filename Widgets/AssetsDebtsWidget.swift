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
            // The asset side rather than the debt one because assets are the
            // larger half of what it draws; NetWorthStats and Cagr stay on their
            // Overview foci, where their figures live and nowhere else.
            .widgetURL(DeepLink.book(.assets).url)
        }
    }
}
