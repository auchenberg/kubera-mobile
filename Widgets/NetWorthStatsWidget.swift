import SwiftUI
import WidgetKit

struct NetWorthStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorthStatsWidget", provider: KuberaProvider()) { entry in
            NetWorthStatsView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Net Worth")
        .description("Net worth with 1-day, 1-year, and YTD change.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryRectangular, .accessoryCircular,
        ])
    }
}

struct NetWorthStatsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KuberaEntry

    var body: some View {
        switch entry.state {
        case .signedOut:
            SignedOutView(family: family)
        case .data(let snapshot):
            NetWorthWidgetContent(
                snapshot: snapshot,
                trends: entry.trends,
                settings: entry.settings,
                family: family
            )
            .widgetURL(URL(string: "kuberawidgets://"))
        }
    }
}
