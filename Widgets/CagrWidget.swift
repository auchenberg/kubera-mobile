import SwiftUI
import WidgetKit

/// Percent-only growth widget modeled on the "CAGR • YTD" block of Kubera's
/// dashboard: the portfolio's own year-to-date growth over the market
/// benchmarks it is competing with. Shows no absolute amounts, which also
/// makes it a natural fit for privacy mode.
///
/// Despite the name, nothing here is a CAGR: the big figure is `trends.ytd` and
/// the small ones are the benchmarks' YTD. The name comes from the dashboard
/// block this mirrors, whose heading reads "CAGR • YTD". So when Kubera's own
/// CAGR arrived (`Kubera.MCP.fetchCAGR`), there was no computed rate here to
/// replace — a small widget has room for one headline figure, and YTD is the one
/// it was built around. Wiring the served rate in would mean deciding which of
/// the two this widget is for, not swapping a number.
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
            .widgetURL(DeepLink.url(for: .growth))
        }
    }
}
