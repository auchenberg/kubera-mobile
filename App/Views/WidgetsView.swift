import SwiftUI
import UIKit
import WidgetKit

/// The widget gallery: one horizontally scrolling row per family, each card the
/// real widget view from `Shared/WidgetViews.swift` at the family's true point
/// size *on this device* — see `WidgetPreviewSize`. Nothing here is a mockup or
/// a screenshot, and nothing is scaled down, so a card is a fixed width the
/// page cannot reflow: two mediums side by side are wider than any iPhone,
/// which is what the horizontal scrollers are for.
struct WidgetsView: View {
    @Environment(AppStore.self) private var store
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

    /// This device's widget footprints, or the nearest class Apple publishes.
    /// Computed rather than stored: it is read from the screen, and a stored
    /// copy would outlive a Display Zoom change that the app is relaunched for
    /// but the view struct is not necessarily rebuilt by.
    private var footprints: WidgetPreviewSize.Match { WidgetPreviewSize.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader("Widgets")
                        .tabTopAnchor()
                        .padding(.horizontal, margin)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    introCard

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
            // No nav title: `ScreenHeader` is this screen's heading, so the tab
            // opens at the same height as the Overview. A large title would
            // reserve a bar above the content and start the page lower.
            .toolbar(.hidden, for: .navigationBar)
            // Scrolling only: the status line carries the result of the last
            // refresh, including its errors, and a reset that swallowed a
            // failure would be a reset that hides it.
            .scrollsToTopOnTabReset(of: .widgets)
            // iOS offers no API to open the widget gallery, so the button
            // walks through the manual steps instead.
            .sheet(isPresented: $showingAddSheet) {
                AddWidgetsSheet()
            }
        }
    }

    // MARK: - Chrome

    /// What the other tabs lead with: the title on the page, then one card. The
    /// bottom padding is on top of `SectionTitle`'s own top padding, so the
    /// intro reads as its own block rather than as the first gallery's heading.
    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Kubera can show widgets on your homescreen. Below are a preview of the widgets we support.")
                    .font(.subheadline)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                // Only when it is true. The previews claim to be actual size,
                // so on a screen Apple has published no widget sizes for they
                // have to say they are the nearest thing instead of quietly
                // being a few points wrong.
                if !footprints.isExact {
                    Text("Apple publishes no widget sizes for this screen, so these are the closest size it does publish — a few points out.")
                        .font(.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actions
            }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, 12)
    }

    private var lockScreenNote: some View {
        Text("Shown on a stand-in wallpaper. On the Lock Screen these take their colour from whatever wallpaper is behind them, so the real thing follows your wallpaper rather than this.")
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
    /// it — this is the discoverable spelling, not the primary way. Small
    /// because they share the intro card with the copy above them.
    @ViewBuilder
    private var actions: some View {
        let add = CompactButton(
            title: "Add widgets",
            systemImage: "plus",
            kind: .prominent,
            size: .small
        ) {
            showingAddSheet = true
        }
        let refresh = CompactButton(
            title: "Update data",
            systemImage: "arrow.clockwise",
            size: .small,
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
        let size = footprints.points(for: family)
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
            // A Lock Screen accessory is vibrancy over the wallpaper, so it
            // has no colour of its own — it takes the appearance the wallpaper
            // forces. The plate follows the app's appearance and the content is
            // told to resolve against the same one, so `.primary`/`.secondary`
            // land legibly on whichever plate is showing.
            widget
                .environment(\.colorScheme, plateScheme)
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
                .modifier(CircularAccessoryClip(
                    isCircular: family == .accessoryCircular,
                    edge: plateEdgeColor
                ))
                .padding(lockPlateInset)
                .frame(height: WidgetPreviewSize.lockPlateHeight + lockPlateInset * 2)
                .background { wallpaper }
                .clipShape(shape)
                .overlay(shape.strokeBorder(plateEdgeColor.opacity(wallpaperEdge), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.10), radius: 8, y: 3)
        }
    }

    /// Stands in for a Lock Screen wallpaper, following the app's appearance.
    ///
    /// A real accessory is vibrancy over whatever wallpaper is behind it, so it
    /// has no fixed appearance of its own — which is why a permanently dark
    /// plate read as "dark mode leaked in" on an otherwise light page. Note this
    /// tracks the *app's* appearance, not the user's actual wallpaper; the two
    /// can disagree, which is what the caption under the row admits.
    ///
    /// Contrast measured against the gradient's worst stop for each appearance,
    /// with `.secondary` taken as 60% of `.primary` over the plate. Recorded so
    /// the next change can be checked rather than eyeballed — the dark plate's
    /// light end started at 4.05:1 for secondary text and had to come down.
    ///
    /// - dark plate: primary 9.7:1 lightest / 15.3:1 darkest, secondary 4.7:1
    /// - light plate: primary 15.7:1 lightest / 11.2:1 darkest, secondary 4.6:1
    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: plateIsLight
                    ? [
                        Color(red: 0.86, green: 0.87, blue: 0.92),
                        Color(red: 0.72, green: 0.74, blue: 0.83),
                    ]
                    : [
                        Color(red: 0.24, green: 0.26, blue: 0.38),
                        Color(red: 0.13, green: 0.14, blue: 0.23),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill((plateIsLight ? Color.white : Color.white).opacity(plateIsLight ? 0.55 : 0.20))
                .frame(width: 150)
                .blur(radius: 50)
                .offset(x: -55, y: -45)
        }
    }

    /// The plate follows the app rather than being fixed dark.
    private var plateIsLight: Bool { colorScheme != .dark }

    /// What the accessory content resolves its `.primary`/`.secondary` against,
    /// so the vibrancy stand-in matches the plate it sits on.
    private var plateScheme: ColorScheme { plateIsLight ? .light : .dark }

    /// The hairline and the circular ring have to invert with the plate or they
    /// disappear into it.
    private var plateEdgeColor: Color { plateIsLight ? .black : .white }

    /// The wallpaper plate is a fixed dark slab in both appearances, so its edge
    /// cannot come from `Theme` and pick up contrast awareness with it — a 14%
    /// hairline is invisible to someone who asked for Increase Contrast.
    private var wallpaperEdge: Double {
        contrast == .increased ? 0.45 : 0.14
    }

    private func plateWidth(for family: WidgetFamily) -> CGFloat {
        let size = footprints.points(for: family)
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
    /// Inverts with the plate, or the ring disappears into a light wallpaper.
    let edge: Color

    func body(content: Content) -> some View {
        if isCircular {
            // A ring rather than a filled disc: a translucent fill over the
            // plate went muddy and read as a UI well the real widget does not
            // have. The ring is only there to show where the system clips.
            content
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(edge.opacity(0.28), lineWidth: 1))
        } else {
            content
        }
    }
}

/// Widget footprints in points, keyed on the portrait screen size the device
/// reports.
///
/// Every row is transcribed verbatim from Apple's Human Interface Guidelines,
/// "Widgets › Specifications › iOS dimensions" (page last revised 16 December
/// 2025):
/// https://developer.apple.com/design/human-interface-guidelines/widgets
///
/// Nothing is interpolated. WidgetKit exposes no API to ask a family for its
/// footprint, so a table is the only way — and a plausible-looking number
/// invented for a missing row would defeat the one thing a true-size preview is
/// for. Apple publishes no row for the 402pt and 440pt screens the iPhone
/// 16/17 Pro and Pro Max report, so those fall to the nearest published class
/// and the page says so rather than claiming precision it does not have.
///
/// Large and extra-large are omitted because this app ships neither.
private enum WidgetPreviewSize {
    struct Footprint {
        let screen: CGSize
        let small: CGSize
        let medium: CGSize
        /// Absent where the table prints N/A, which is only the 320×568 class —
        /// it predates Lock Screen widgets, though a zoomed iPhone SE still
        /// reports it.
        let accessory: Accessory?

        /// Scalars rather than sizes so the table below stays legible against
        /// the source: small and circular are square, and every published row
        /// gives inline the same 26pt height.
        init(
            _ screen: (CGFloat, CGFloat),
            small: CGFloat,
            medium: (CGFloat, CGFloat),
            circular: CGFloat? = nil,
            rectangular: (CGFloat, CGFloat)? = nil,
            inline: CGFloat? = nil
        ) {
            self.screen = CGSize(width: screen.0, height: screen.1)
            self.small = CGSize(width: small, height: small)
            self.medium = CGSize(width: medium.0, height: medium.1)
            if let circular, let rectangular, let inline {
                accessory = Accessory(
                    circular: CGSize(width: circular, height: circular),
                    rectangular: CGSize(width: rectangular.0, height: rectangular.1),
                    inline: CGSize(width: inline, height: 26)
                )
            } else {
                accessory = nil
            }
        }
    }

    struct Accessory {
        let circular: CGSize
        let rectangular: CGSize
        let inline: CGSize
    }

    /// A resolved lookup: the footprints to lay out against, and whether they
    /// are actually this device's.
    struct Match {
        let footprint: Footprint
        /// False when this device's screen is not one the guidelines publish,
        /// or when it is but publishes no accessory sizes — this page renders
        /// every family, so either way the previews are the nearest published
        /// class rather than the real thing.
        let isExact: Bool

        func points(for family: WidgetFamily) -> CGSize {
            switch family {
            case .systemMedium: return footprint.medium
            case .accessoryCircular: return accessory.circular
            case .accessoryRectangular: return accessory.rectangular
            case .accessoryInline: return accessory.inline
            default: return footprint.small
            }
        }

        private var accessory: Accessory {
            footprint.accessory ?? WidgetPreviewSize.fallbackAccessory
        }
    }

    /// For the one published row that omits accessory sizes. These are the
    /// 375×667 figures: the only device that reports 320×568 is a zoomed
    /// iPhone SE, so it borrows the class it is a zoom of.
    static let fallbackAccessory = Accessory(
        circular: CGSize(width: 68, height: 68),
        rectangular: CGSize(width: 153, height: 68),
        inline: CGSize(width: 225, height: 26)
    )

    /// The class the previews were laid out against before this table existed.
    /// Also the fallback if the nearest-match ever comes up empty, so the
    /// lookup cannot return nothing.
    static let standard = Footprint(
        (393, 852), small: 158, medium: (338, 158), circular: 72, rectangular: (160, 72), inline: 234
    )

    private static let table: [Footprint] = [
        Footprint((430, 932), small: 170, medium: (364, 170), circular: 76, rectangular: (172, 76), inline: 257),
        Footprint((428, 926), small: 170, medium: (364, 170), circular: 76, rectangular: (172, 76), inline: 257),
        Footprint((414, 896), small: 169, medium: (360, 169), circular: 76, rectangular: (160, 72), inline: 248),
        Footprint((414, 736), small: 159, medium: (348, 157), circular: 76, rectangular: (170, 76), inline: 248),
        standard,
        Footprint((390, 844), small: 158, medium: (338, 158), circular: 72, rectangular: (160, 72), inline: 234),
        Footprint((375, 812), small: 155, medium: (329, 155), circular: 72, rectangular: (157, 72), inline: 225),
        Footprint((375, 667), small: 148, medium: (321, 148), circular: 68, rectangular: (153, 68), inline: 225),
        Footprint((360, 780), small: 155, medium: (329, 155), circular: 72, rectangular: (157, 72), inline: 225),
        Footprint((320, 568), small: 141, medium: (292, 141)),
    ]

    /// This device's row, or the nearest published one.
    ///
    /// Keyed on the screen rather than on a `GeometryReader`, because the
    /// table's key *is* the screen size and a view's size is never that — it is
    /// the window minus safe areas and the tab bar, which could not tell
    /// 375×812 from 375×667, two classes whose footprints differ by 7pt. Going
    /// through the screen also gets Display Zoom right for free: a zoomed phone
    /// reports the smaller size, which the guidelines already list as its own
    /// row.
    ///
    /// `UIScreen.main` is soft-deprecated and wrong under multitasking, so the
    /// window scene's screen is preferred; the fallback only matters before a
    /// scene has connected. This app is iPhone-only and portrait-only, so
    /// neither the deprecation nor multitasking is live here.
    static var current: Match {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return match(screen: (scene?.screen ?? UIScreen.main).bounds.size)
    }

    /// Normalised to portrait, so a bounds read that arrives rotated cannot
    /// silently select a different row.
    static func match(screen: CGSize) -> Match {
        let portrait = CGSize(
            width: min(screen.width, screen.height),
            height: max(screen.width, screen.height)
        )
        let nearest = table.min {
            distance($0.screen, portrait) < distance($1.screen, portrait)
        } ?? standard
        return Match(
            footprint: nearest,
            isExact: nearest.screen == portrait && nearest.accessory != nil
        )
    }

    /// Width dominates and height only breaks ties: width is what the Home
    /// Screen grid is laid out against, and the two duplicated widths in the
    /// table are the only cases height has to settle. A screen wider than
    /// anything published lands on the widest row, since that is the nearest.
    private static func distance(_ row: CGSize, _ screen: CGSize) -> (CGFloat, CGFloat) {
        (abs(row.width - screen.width), abs(row.height - screen.height))
    }

    /// One height for every accessory plate, so the Lock Screen row reads as a
    /// single strip of wallpaper rather than three ragged slabs. Also the
    /// tallest accessory any published row has, so no widget overflows it.
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
