import SwiftUI
import WidgetKit

struct WidgetsView: View {
    @Environment(AppStore.self) private var store
    @State private var status: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Three widgets are available in the iOS widget gallery. Previews below use your live data.")
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.dim)

                    SectionTitle("Net Worth · small, medium & Lock Screen")
                    previewCard {
                        NetWorthWidgetContent(
                            snapshot: snapshot,
                            trends: trends,
                            settings: store.settings,
                            family: .systemSmall
                        )
                        .widgetPreviewFrame(family: .systemSmall)
                    }
                    previewCard {
                        NetWorthWidgetContent(
                            snapshot: snapshot,
                            trends: trends,
                            settings: store.settings,
                            family: .systemMedium
                        )
                        .widgetPreviewFrame(family: .systemMedium)
                    }

                    SectionTitle("CAGR · small")
                    previewCard {
                        CagrWidgetContent(
                            snapshot: snapshot,
                            trends: trends,
                            comps: comps,
                            settings: store.settings,
                            family: .systemSmall
                        )
                        .widgetPreviewFrame(family: .systemSmall)
                    }

                    SectionTitle("Assets vs debts · medium")
                    previewCard {
                        AssetsDebtsWidgetContent(
                            snapshot: snapshot,
                            settings: store.settings,
                            family: .systemMedium
                        )
                        .widgetPreviewFrame(family: .systemMedium)
                    }

                    SectionTitle("Widget options")
                    optionsCard

                    updateSection

                    SectionTitle("How to add a widget")
                    howToCard

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Theme.background)
            .refreshable { await updateWidgetData() }
            .navigationTitle("Widgets")
        }
    }

    // MARK: - Sections

    private func previewCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        Card {
            content().frame(maxWidth: .infinity)
        }
    }

    private var optionsCard: some View {
        Card(padding: .cardRows) {
            VStack(spacing: 0) {
                optionRow(
                    "Privacy mode",
                    description: "Mask all amounts on the Home Screen",
                    value: store.settings.privacyMode
                ) { $0.privacyMode = $1 }

                RowDivider()
                optionRow(
                    "Compact numbers",
                    description: "Show $1.24M instead of $1,240,000",
                    value: store.settings.compactNumbers
                ) { $0.compactNumbers = $1 }
            }
        }
    }

    private func optionRow(
        _ label: String,
        description: String,
        value: Bool,
        apply: @escaping (inout WidgetSettings, Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in store.updateSettings { apply(&$0, newValue) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 12)
    }

    private var updateSection: some View {
        VStack(spacing: 10) {
            ActionButton(
                title: "Update widget data now",
                isLoading: store.refreshing,
                action: { Task { await updateWidgetData() } }
            )

            if let status {
                Text(status)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }

    private var howToCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                step("1. Long-press your Home Screen, then tap Edit → Add Widget.", color: Theme.text)
                step("2. Search for “Kubera Widgets”.", color: Theme.text)
                step("3. Pick a widget and size, then tap Add Widget.", color: Theme.text)
                step(
                    "Widgets refresh on their own roughly every 30–60 minutes, and instantly whenever you open this app.",
                    color: Theme.dim
                )
            }
        }
    }

    private func step(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(6)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    // MARK: - Data

    /// The previews render the real widget views with the store's observable
    /// widget data, so they re-render live as refreshes land and show exactly
    /// what the Home Screen widgets would show — including empty states.
    /// Sample values appear only before the first snapshot ever lands.
    private var snapshot: PortfolioSnapshot {
        store.snapshot ?? .sample
    }

    private var trends: PortfolioTrends? {
        store.snapshot == nil ? .sample : store.trends
    }

    private var comps: MarketComps? {
        store.snapshot == nil ? .sample : store.comps
    }

    private func updateWidgetData() async {
        status = nil
        do {
            try await store.refresh()
            status = "Widget data updated."
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Preview framing

private extension View {
    /// Draws the widget content at the family's real point size on the widget's
    /// own background, so the preview matches the Home Screen pixel for pixel.
    /// A medium widget is wider than the card it sits in on most iPhones, so it
    /// scales down proportionally rather than clipping.
    func widgetPreviewFrame(family: WidgetFamily) -> some View {
        let size = WidgetPreviewSize.points(for: family)
        let plate = padding(16)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(WidgetTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        return GeometryReader { geo in
            plate
                .scaleEffect(min(1, geo.size.width / size.width))
                .frame(width: geo.size.width, height: size.height)
        }
        .frame(height: size.height)
    }
}

private enum WidgetPreviewSize {
    static func points(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: return CGSize(width: 338, height: 158)
        default: return CGSize(width: 158, height: 158)
        }
    }
}
