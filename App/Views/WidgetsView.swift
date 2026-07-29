import SwiftUI
import WidgetKit

struct WidgetsView: View {
    @Environment(AppStore.self) private var store
    @State private var status: String?
    @State private var showingAddSheet = false

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

                    ActionButton(title: "Add widgets") {
                        showingAddSheet = true
                    }
                    .padding(.top, 24)

                    updateSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Theme.background)
            .refreshable { await updateWidgetData() }
            .navigationTitle("Widgets")
            // iOS offers no API to open the widget gallery, so the button
            // walks through the manual steps instead.
            .sheet(isPresented: $showingAddSheet) {
                AddWidgetsSheet()
            }
        }
    }

    // MARK: - Sections

    private func previewCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        Card {
            content().frame(maxWidth: .infinity)
        }
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

// MARK: - Add widgets walkthrough

/// iOS has no public API to open the Home Screen widget gallery, so the
/// "Add widgets" button walks through the manual steps instead.
private struct AddWidgetsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add widgets to your Home Screen")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, 28)
                .padding(.bottom, 20)

            step(
                symbol: "hand.tap",
                text: "Long-press your Home Screen, then tap Edit → Add Widget."
            )
            step(
                symbol: "magnifyingglass",
                text: "Search for “Kubera Mobile”."
            )
            step(
                symbol: "plus.square.on.square",
                text: "Pick a widget and size, then tap Add Widget."
            )

            Text("Widgets refresh on their own roughly every 30–60 minutes, and instantly whenever you open this app.")
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.dim)
                .padding(.top, 16)

            Spacer(minLength: 16)

            ActionButton(title: "Done") { dismiss() }
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func step(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 32)
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}
