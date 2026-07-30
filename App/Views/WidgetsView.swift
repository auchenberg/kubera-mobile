import SwiftUI
import WidgetKit

/// The widget gallery: one horizontally scrolling row per family, each card the
/// real widget view from `Shared/WidgetViews.swift` at the family's true point
/// size. Nothing here is a mockup or a screenshot, and nothing is scaled down —
/// a medium widget is 338pt wide and simply does not fit a phone's width beside
/// a page margin, which is what the horizontal scrollers are for.
struct WidgetsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var status: String?
    @State private var showingAddSheet = false

    /// Chrome around the Lock Screen footprint, which does scale — the widget
    /// inside it must not, so it is padding rather than a frame.
    @ScaledMetric(relativeTo: .caption) private var lockPlateInset: CGFloat = 18

    /// The galleries bleed to the screen edge so a peek of the next card is
    /// visible, so the page margin is applied per element rather than to the
    /// whole column.
    private let margin: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro
                    actions
                        .padding(.top, 14)
                    settingsLink
                        .padding(.top, 14)

                    sectionTitle("Small")
                    gallery {
                        card("Net Worth", family: .systemSmall) {
                            netWorth(.systemSmall)
                        }
                        card("CAGR • YTD", family: .systemSmall) {
                            cagr(.systemSmall)
                        }
                    }

                    sectionTitle("Medium")
                    gallery {
                        card("Net Worth", family: .systemMedium) {
                            netWorth(.systemMedium)
                        }
                        card("Assets vs Debts", family: .systemMedium) {
                            assetsDebts(.systemMedium)
                        }
                    }

                    sectionTitle("Lock Screen")
                    lockScreenNote
                    gallery {
                        card("Rectangular", family: .accessoryRectangular) {
                            netWorth(.accessoryRectangular)
                        }
                        card("Circular", family: .accessoryCircular) {
                            netWorth(.accessoryCircular)
                        }
                        card("Inline", family: .accessoryInline) {
                            netWorth(.accessoryInline)
                        }
                    }

                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 20)
                            .padding(.horizontal, margin)
                    }
                }
            }
            // Instead of a trailing spacer, which would double against the
            // minimizing tab bar.
            .safeAreaPadding(.bottom)
            .background(Theme.background)
            .softTopScrollEdge()
            .refreshable { await updateWidgetData() }
            .navigationTitle("Widgets")
            // iOS offers no API to open the widget gallery, so the button
            // walks through the manual steps instead.
            .sheet(isPresented: $showingAddSheet) {
                AddWidgetsSheet()
            }
        }
    }

    // MARK: - Chrome

    private var intro: some View {
        Text("Three widgets, drawn here exactly as they land on your Home Screen and Lock Screen — real size, your live data.")
            .font(.subheadline)
            .lineSpacing(4)
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, margin)
    }

    /// Privacy mode and Compact numbers stay in Settings because they change the
    /// app as well as the widgets; this link is the discoverability fix for that.
    private var settingsLink: some View {
        Button {
            openURL(DeepLink.settings.url)
        } label: {
            HStack(spacing: 4) {
                Text("These previews use your Settings")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, margin)
    }

    private var lockScreenNote: some View {
        Text("Shown on a stand-in wallpaper. On the Lock Screen these render in white vibrancy over whatever is behind them.")
            .font(.footnote)
            .lineSpacing(3)
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, margin)
            .padding(.bottom, 10)
    }

    private func sectionTitle(_ title: String) -> some View {
        SectionTitle(title)
            .padding(.horizontal, margin)
    }

    /// Both actions at the top, sized to their labels. They used to be two
    /// full-width filled slabs at the bottom of the page, which in light mode
    /// were the heaviest things on a screen whose whole point is the previews
    /// above them. Refresh stays secondary because pull-to-refresh already does
    /// it — this is the discoverable spelling, not the primary way.
    @ViewBuilder
    private var actions: some View {
        let add = CompactButton(
            title: "Add widgets",
            systemImage: "plus",
            kind: .prominent
        ) {
            showingAddSheet = true
        }
        let refresh = CompactButton(
            title: "Update data",
            systemImage: "arrow.clockwise",
            isLoading: store.refreshing
        ) {
            Task { await updateWidgetData() }
        }

        // Side by side until the labels stop fitting, which they do well before
        // AX5 given two capsules and their symbols.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                add
                refresh
            }
            VStack(alignment: .leading, spacing: 10) {
                add
                refresh
            }
        }
        .padding(.horizontal, margin)
    }

    // MARK: - Gallery

    /// One family's row. The horizontal inset lives *inside* the scroller, so
    /// the first card sits at the page margin while the next one peeks past the
    /// trailing edge — the affordance that replaces page dots.
    private func gallery<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                content()
            }
            .scrollTargetLayout()
            // Room for the shadow the plates cast.
            .padding(.vertical, 4)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, margin)
    }

    private func card<Content: View>(
        _ name: String,
        family: WidgetFamily,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let width = plateWidth(for: family)
        return VStack(alignment: .leading, spacing: 8) {
            plate(family: family, content: content)
            Text(name)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                // Bounded so the caption wraps instead of stretching the card:
                // inside a horizontal scroller a Text has unlimited width.
                .frame(width: width, alignment: .leading)
        }
        // A container rather than a combined element: the announcement says
        // which widget this is, and the figures inside stay individually
        // readable instead of collapsing into one run.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(familyLabel(family)) preview")
    }

    private func familyLabel(_ family: WidgetFamily) -> String {
        switch family {
        case .systemMedium: return "medium widget"
        case .accessoryInline, .accessoryCircular, .accessoryRectangular: return "Lock Screen widget"
        default: return "small widget"
        }
    }

    /// The widget at its real point size on its own background, so the preview
    /// matches the Home Screen. The plate is outlined because in light mode the
    /// widget's background is nearly the colour of the page behind it; in dark
    /// mode the same outline reads as the widget's edge.
    @ViewBuilder
    private func plate<Content: View>(
        family: WidgetFamily,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let size = WidgetPreviewSize.points(for: family)
        let shape = RoundedRectangle(cornerRadius: family.usesThemedBackground ? 24 : 20, style: .continuous)

        // A widget is a fixed canvas: its text does not grow with the phone's
        // Dynamic Type setting, so clamping is correct here — and only here.
        let widget = content()
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

        if family.usesThemedBackground {
            widget
                .padding(16)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(WidgetTheme.background)
                .clipShape(shape)
                .overlay(shape.strokeBorder(WidgetTheme.border, lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 8, y: 3)
        } else {
            // Accessories are vibrancy-rendered white-on-transparent and would
            // disappear on a light card. The dark appearance is forced so their
            // `.primary`/`.secondary` foregrounds resolve the way vibrancy does.
            widget
                .environment(\.colorScheme, .dark)
                // The inline family is one run of text the system fits beside
                // the clock. Shrinking it keeps the preview readable at large
                // type rather than clipping inside the fixed footprint.
                .lineLimit(family == .accessoryInline ? 1 : nil)
                .minimumScaleFactor(family == .accessoryInline ? 0.7 : 1)
                .frame(width: size.width, height: size.height)
                // The system clips a circular accessory to a circle and draws a
                // faint ring behind it. Without this the preview shows content
                // that would be cut off on the real Lock Screen, which is the
                // one thing a true-size preview exists to prevent.
                .modifier(CircularAccessoryClip(isCircular: family == .accessoryCircular))
                .padding(lockPlateInset)
                .frame(height: WidgetPreviewSize.lockPlateHeight + lockPlateInset * 2)
                .background { wallpaper }
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(wallpaperEdge), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 8, y: 3)
        }
    }

    /// Stands in for a Lock Screen wallpaper: dark, softly graded, with one
    /// blurred highlight so the accessories are read against a photo rather
    /// than a flat swatch.
    /// Lifted well off black and given some hue. Lock Screen accessories are
    /// white-vibrancy, so the plate has to stay dark enough to read them — but a
    /// near-black slab on a light page was the heaviest thing on the screen and
    /// clashed with the light Home Screen cards above it. Indigo at this depth
    /// still clears white text comfortably while reading as a wallpaper swatch
    /// rather than a UI surface.
    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.31, blue: 0.44),
                    Color(red: 0.16, green: 0.17, blue: 0.27),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.20))
                .frame(width: 150)
                .blur(radius: 50)
                .offset(x: -55, y: -45)
        }
    }

    /// The wallpaper plate is a fixed dark slab in both appearances, so its edge
    /// cannot come from `Theme` and pick up contrast awareness with it — a 14%
    /// hairline is invisible to someone who asked for Increase Contrast.
    private var wallpaperEdge: Double {
        contrast == .increased ? 0.45 : 0.14
    }

    private func plateWidth(for family: WidgetFamily) -> CGFloat {
        let size = WidgetPreviewSize.points(for: family)
        return family.usesThemedBackground ? size.width : size.width + lockPlateInset * 2
    }

    // MARK: - Widget content
    //
    // `family` is passed explicitly: `\.widgetFamily` is an environment key only
    // WidgetKit populates, so the app cannot set it.

    private func netWorth(_ family: WidgetFamily) -> some View {
        NetWorthWidgetContent(
            snapshot: snapshot,
            trends: trends,
            settings: store.settings,
            family: family
        )
    }

    private func cagr(_ family: WidgetFamily) -> some View {
        CagrWidgetContent(
            snapshot: snapshot,
            trends: trends,
            comps: comps,
            settings: store.settings,
            family: family
        )
    }

    private func assetsDebts(_ family: WidgetFamily) -> some View {
        AssetsDebtsWidgetContent(
            snapshot: snapshot,
            settings: store.settings,
            family: family
        )
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

/// Reproduces what the system does to an `.accessoryCircular` widget: clips it
/// to a circle and sits it on the faint ring the Lock Screen draws behind one.
/// Applied conditionally rather than at the call site so both branches keep the
/// same concrete view type.
private struct CircularAccessoryClip: ViewModifier {
    let isCircular: Bool

    func body(content: Content) -> some View {
        if isCircular {
            // A ring rather than a filled disc: a translucent white fill over
            // the plate went muddy grey and read as a UI well the real widget
            // does not have. The ring is only there to show where the system
            // clips.
            content
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        } else {
            content
        }
    }
}

private enum WidgetPreviewSize {
    /// Footprints vary by a few points across devices; these are the iPhone
    /// 15/16 Pro figures, which is what the previews are laid out against.
    static func points(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: return CGSize(width: 338, height: 158)
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryCircular: return CGSize(width: 76, height: 76)
        case .accessoryInline: return CGSize(width: 172, height: 26)
        default: return CGSize(width: 158, height: 158)
        }
    }

    /// One height for every accessory plate, so the Lock Screen row reads as a
    /// single strip of wallpaper rather than three ragged slabs.
    static let lockPlateHeight: CGFloat = 76
}

// MARK: - Add widgets walkthrough

/// iOS has no public API to open the Home Screen widget gallery, so the
/// "Add widgets" button walks through the manual steps instead.
private struct AddWidgetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Relative to the glyph's own style, not the row's `.body` label, so the
    /// symbol can never outgrow the column it is centred in.
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add widgets to your Home Screen")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.text)
                .padding(.top, 28)
                .padding(.bottom, 20)

            // Scrolls because the steps outgrow the medium detent at
            // accessibility type sizes.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                    step(
                        symbol: "lock",
                        text: "For the Lock Screen: long-press the Lock Screen, tap Customize, then the area under the clock."
                    )

                    Text("Widgets refresh on their own roughly every 30–60 minutes, and instantly whenever you open this app.")
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
            }
            .scrollIndicators(.hidden)

            ActionButton(title: "Done") { dismiss() }
                .padding(.top, 16)
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: symbolWidth)
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

#if DEBUG
#Preview("Widgets") {
    WidgetsView()
        .environment(AppStore())
}

#Preview("Widgets — dark") {
    WidgetsView()
        .environment(AppStore())
        .preferredColorScheme(.dark)
}

#Preview("Widgets — AX5") {
    WidgetsView()
        .environment(AppStore())
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
