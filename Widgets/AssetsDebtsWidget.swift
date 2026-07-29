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
            .widgetURL(URL(string: "kuberawidgets://"))
        }
    }
}
