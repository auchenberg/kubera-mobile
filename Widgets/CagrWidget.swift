import SwiftUI
import WidgetKit

/// Percent-only growth widget modeled on the "CAGR • YTD" block of Kubera's
/// dashboard: the portfolio's own year-to-date growth over the market
/// benchmarks it is competing with. Shows no absolute amounts, which also
/// makes it a natural fit for privacy mode.
struct CagrWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetWorthCagrWidget", provider: KuberaProvider()) { entry in
            CagrView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("CAGR • YTD")
        .description("Year-to-date net worth growth next to the S&P 500, Dow Jones, and Bitcoin.")
        .supportedFamilies([.systemSmall])
    }
}

struct CagrView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KuberaEntry

    var body: some View {
        switch entry.state {
        case .signedOut:
            SignedOutView(family: family)
        case .data(let snapshot):
            CagrWidgetContent(
                snapshot: snapshot,
                trends: entry.trends,
                comps: entry.comps,
                settings: entry.settings,
                family: family
            )
            .widgetURL(URL(string: "kubera://"))
        }
    }
}
