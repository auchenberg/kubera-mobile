import Accessibility
import Charts
import SwiftUI
import UIKit

/// The Overview screen: a greeting, one hero number, the chart that reads it
/// out, then the supporting modules Kubera's own dashboard carries — Assets and
/// Debts with their 1 DAY / 1 YEAR lines, the CAGR • YTD block with market
/// comps, allocation, and top holdings.
///
/// Phase 2 of `specs/overview-dashboard.md`: drag-to-scrub that retargets the
/// hero, Liquid Glass on the controls layer only, and `.numericText` transitions
/// on every figure that can change.
///
/// All arithmetic lives in `OverviewChart` and `OverviewModules` so it can be
/// unit tested; this file is layout, gesture, and haptics only.
struct OverviewView: View {
    /// The module a widget tap asked to see. Cleared once scrolled to, so the
    /// next tap on the same widget scrolls again rather than being swallowed.
    @Binding var focus: DeepLink.OverviewFocus?

    init(focus: Binding<DeepLink.OverviewFocus?> = .constant(nil)) {
        _focus = focus
    }

    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Geometry that has to grow with the text beside it. `relativeTo:` names
    /// that text: a width scaled against `.body` next to a `.caption2` label
    /// drifts away from it as the type size climbs.
    ///
    /// The hero keeps a point size rather than a text style because its currency
    /// symbol is set at 55% of it and lifted by 30% of it, and a text style hands
    /// back no number to take a fraction of.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40
    @ScaledMetric(relativeTo: .caption2) private var trendLabelWidth: CGFloat = 42
    /// Keeps the menu button at the 44pt minimum without padding the greeting row.
    @ScaledMetric(relativeTo: .body) private var menuTapTarget: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var ytdColumnWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .subheadline) private var cagrColumnWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var sharePercentWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var rankWidth: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var legendDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .footnote) private var allocationDotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var pillVerticalPadding: CGFloat = 7
    @ScaledMetric(relativeTo: .footnote) private var allocationBarHeight: CGFloat = 12
    /// Fixed per type size rather than measured: a bubble that resizes as the
    /// digits change jitters under the finger, and a constant width means the
    /// clamp against the plot edges is a constant too.
    @ScaledMetric(relativeTo: .caption2) private var scrubTooltipWidth: CGFloat = 148

    @State private var range: ChartRange = .ytd
    @State private var compositionLevel: OverviewModules.CompositionLevel = .sheet
    @State private var errorMessage: String?
    /// Parsed once per load rather than per render — each parse walks the whole
    /// series through a DateFormatter.
    @State private var netWorthSeries: [ChartPoint] = []
    @State private var assetSeries: [ChartPoint] = []
    @State private var debtSeries: [ChartPoint] = []
    /// Investable is not on `PortfolioSnapshot`; it comes from the detail fetch,
    /// or from the history series when that has not landed.
    @State private var investableSeries: [ChartPoint] = []

    /// Fixed when the screen appears. `Greeting.phrase` reseeds every hour, and
    /// reading the clock per render would let the greeting change underneath a
    /// scroll.
    @State private var greetingDate = Date()
    @State private var showsGreetingNote = false

    /// The point under the finger, or nil when nobody is scrubbing. Everything
    /// the scrub changes — hero, delta, rule, dot, tooltip — reads off this.
    @State private var scrubbed: ChartPoint?
    /// What the current drag has been decided to mean. Reset at the start of
    /// every drag rather than only on release, so a gesture the `ScrollView`
    /// cancels mid-flight can't leave scrubbing wedged off.
    @State private var scrubIntent: OverviewChart.ScrubIntent = .undecided
    /// When the last selection tick fired, for rate limiting.
    @State private var lastTick = Date.distantPast
    /// Held in `@State` so the generators survive re-renders with their
    /// `prepare()` still in effect — a generator rebuilt every render is a
    /// generator that is never warm, and the first tick of every drag lands late.
    @State private var selectionHaptics = UISelectionFeedbackGenerator()
    @State private var engageHaptics = UIImpactFeedbackGenerator(style: .light)

    /// Falls back to the sample portfolio so the screen never renders empty —
    /// a signed-out or pre-first-fetch launch still shows the real layout.
    private var snapshot: PortfolioSnapshot { store.snapshot ?? .sample }
    /// The MCP detail fetch. Nil until it lands, and every field inside it is
    /// optional, so each module it feeds hides itself rather than printing 0.
    private var detail: PortfolioDetail? { store.detail }
    /// The figure the hero prints: `PortfolioDetail.investableTotal` when the
    /// detail fetch carries it, else the newest history point recent enough to
    /// stand beside today's net worth. Derived rather than cached, so it can't
    /// lag behind a detail fetch that lands outside a reload.
    private var investableNow: Double? {
        OverviewModules.investable(
            detail: detail,
            series: investableSeries,
            now: Date(),
            calendar: .current
        )
    }
    private var currency: String { snapshot.currency }
    private var masked: Bool { store.settings.privacyMode }
    private var compactNumbers: Bool { store.settings.compactNumbers }

    /// The hero card's inset. Named because the chart cancels it out to bleed to
    /// the card's edges, and the two must stay in step.
    private static let cardInset: CGFloat = 16

    private var visiblePoints: [ChartPoint] {
        OverviewChart.filter(netWorthSeries, to: range, now: Date(), calendar: .current)
    }

    /// The investable curve for the same window, drawn only when it has a shape
    /// of its own. A single point would render as a dot with a legend entry
    /// promising a series that isn't there.
    private var visibleInvestablePoints: [ChartPoint] {
        let points = OverviewChart.filter(investableSeries, to: range, now: Date(), calendar: .current)
        return points.count >= 2 ? points : []
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                content
                    .onChange(of: focus) { _, new in
                        guard let new else { return }
                        // Anchored .top rather than .center: these are section
                        // headings, and centring one leaves its card half
                        // scrolled past.
                        // A programmatic scroll across a whole screen is the
                        // large-area movement Reduce Motion exists for; the jump
                        // still lands on the anchor.
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                            scroller.scrollTo(new.anchor, anchor: .top)
                        }
                        focus = nil
                    }
            }
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greeting
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        // The greeting, not the hero card: a re-tap should land
                        // where the screen starts, and the hero's own anchor is
                        // a module a widget can ask for.
                        .tabTopAnchor()

                    if let errorMessage {
                        Card {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.negative)
                        }
                        .padding(.bottom, 12)
                    }

                    heroCard
                        .padding(.bottom, 12)
                        .id(DeepLink.OverviewFocus.netWorth.anchor)

                    if shows(.assetsDebts) {
                        statPair
                            .id(DeepLink.OverviewFocus.assetsDebts.anchor)
                    }

                    if shows(.balances) {
                        balancePair
                    }

                    if shows(.growth), !growthRows.isEmpty || !comps.isEmpty {
                        // Benchmarks alone are not your CAGR, so the heading
                        // stops claiming to be when your own rows are missing.
                        SectionTitle(growthRows.isEmpty ? "Market" : "CAGR • YTD")
                            .id(DeepLink.OverviewFocus.growth.anchor)
                        growthCard
                    }

                    if shows(.allocation), !allocationSegments.isEmpty {
                        SectionTitle("Allocation")
                        allocationCard
                    }

                    if shows(.assetFlow), assetFlow.isMeaningful {
                        SectionTitle("Asset flow")
                        assetFlowCard
                    }

                    if shows(.composition), !compositionGroups.isEmpty {
                        SectionTitle("Composition")
                        compositionCard
                    }

                    if shows(.holdings), !snapshot.topHoldings.isEmpty {
                        SectionTitle("Top holdings")
                        holdingsCard
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .softTopScrollEdge()
            // No nav title: the greeting is this screen's heading, the way
            // Kubera's own dashboard opens. A bar with "Overview" in it would
            // either compete with the greeting or cost 44pt of empty chrome
            // above it.
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await reload() }
            .task {
                // Warm both generators once; the first tick of a cold generator
                // arrives noticeably after the finger has already moved.
                selectionHaptics.prepare()
                engageHaptics.prepare()
                await reload()
            }
            // Scrolling is this tab's whole reset. The range pill and the
            // sheet/section toggle are picks the reader made and expects to
            // find where they left them, and `errorMessage` reports a refresh
            // that actually failed — a gesture for getting back to the top has
            // no business silencing it.
            .scrollsToTopOnTabReset(of: .overview)
    }

    // MARK: - Greeting

    /// The screen's heading: "Hej, Kenneth", with a quiet marker when the
    /// greeting is a hello the reader may not know.
    private var greeting: some View {
        let phrase = Greeting.phrase(for: greetingDate)

        // The marker is concatenated into the text run rather than placed beside
        // it in an HStack. Neither .center nor .firstTextBaseline lines a round
        // glyph up with cap-height text — one centres on the line box, which
        // sits lower than the letters look, and the other drops it to the
        // baseline. Inside a Text, the type engine does the optical alignment.
        return HStack(spacing: 0) {
            Button {
                if phrase.note != nil { showsGreetingNote = true }
            } label: {
                greetingText(phrase)
            }
            .buttonStyle(.plain)
            .disabled(phrase.note == nil)
            .accessibilityLabel(
                phrase.note == nil
                    ? Greeting.line(for: greetingDate, name: greetingName)
                    : "What this greeting means"
            )
            .popover(isPresented: $showsGreetingNote) {
                Text(phrase.note ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .padding(14)
                    // Without this a popover becomes a sheet on a phone, which
                    // is a whole modal for one sentence.
                    .presentationCompactAdaptation(.popover)
            }
            Spacer(minLength: 0)
            moduleMenu
        }
    }

    /// Which blocks the dashboard shows. A `Menu` of toggles rather than a
    /// screen in Settings: what you are choosing is on-screen behind the menu,
    /// so the result is visible the moment you tap.
    private var moduleMenu: some View {
        Menu {
            ForEach(OverviewModule.hideable) { module in
                Toggle(module.title, isOn: binding(for: module))
            }
            Divider()
            Button("Show all") {
                store.updateSettings { $0.hiddenOverviewModules = [] }
            }
            .disabled(store.settings.hiddenOverviewModules.isEmpty)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: menuTapTarget, height: menuTapTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("Choose which blocks to show")
    }

    private func binding(for module: OverviewModule) -> Binding<Bool> {
        Binding(
            get: { store.settings.hiddenOverviewModules.shows(module) },
            set: { visible in
                store.updateSettings { $0.hiddenOverviewModules.setVisibility(visible, for: module) }
            }
        )
    }

    private func shows(_ module: OverviewModule) -> Bool {
        store.settings.hiddenOverviewModules.shows(module)
    }

    private func greetingText(_ phrase: Greeting.Phrase) -> Text {
        let line = Text(Greeting.line(for: greetingDate, name: greetingName))
            .font(.system(.title, weight: .semibold))
            .kerning(-0.3)
            .foregroundColor(Theme.text)
        guard phrase.note != nil else { return line }
        return line
            + Text("  ")
            + Text(Image(systemName: "info.circle"))
            .font(.system(.subheadline, weight: .semibold))
            .foregroundColor(Theme.dim)
            // The type engine aligns the symbol to the run's baseline, which
            // leaves a subheadline glyph sitting low against title caps. Lifted
            // to the optical centre of the capitals rather than the line box.
            // The 2pt value was chosen by eye and holds across the scale.
            .baselineOffset(2)
    }

    /// The account's own name when the profile fetch has landed, else the
    /// portfolio's. `Greeting.firstName` already treats the generic portfolio
    /// names as nameless, so this hands over whichever it has without checking.
    private var greetingName: String? {
        store.profile?.name ?? store.snapshot?.portfolioName
    }

    /// A footnote, not a badge: `Theme.dim` and no tint, because anything
    /// colored beside a greeting reads as something being wrong.
    // MARK: - Hero + chart

    private var heroCard: some View {
        // Windowed once per render and handed down: the scrub reads these on
        // every touch move, and re-filtering the whole series per subview would
        // do it several times a frame.
        let points = visiblePoints
        let investable = visibleInvestablePoints

        return Card(padding: EdgeInsets(
            top: Self.cardInset,
            leading: Self.cardInset,
            bottom: 12,
            trailing: Self.cardInset
        )) {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader(investable: investable)

                VStack(alignment: .leading, spacing: 4) {
                    heroValue
                        // The one place `minimumScaleFactor` is still the right
                        // answer: the figure is compacted before it is shrunk,
                        // and this only catches a currency code wide enough to
                        // overhang after that.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: heroAmount))

                    heroDelta(points)
                }
                .padding(.top, 2)
                // One statement rather than four elements — "Net worth,
                // $1,240,000, up 3.1 percent, year to date".
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Net worth")
                .accessibilityValue(heroReadout(points))

                if let investableNow {
                    investableLine(investableNow)
                        .padding(.top, 10)
                }

                if points.count >= 2 {
                    // Bleeds past the card's inset so the fill meets both edges.
                    // Inset, the area stopped short of the card and read as a
                    // floating rectangle rather than the card's own graph —
                    // especially against the full-width pill row below it.
                    chart(points, investable: investable)
                        .padding(.top, 14)
                        .padding(.horizontal, -Self.cardInset)
                    endpointLabels(points)
                        .padding(.top, 6)
                } else {
                    emptyChartNote
                        .padding(.top, 16)
                }

                // Offered whenever the series has a shape *somewhere*, not just
                // in the current window — hiding the pills when YTD happens to
                // be empty strands the reader on the one range with no data.
                if netWorthSeries.count >= 2 {
                    rangePills
                        .padding(.top, 12)
                }
            }
        }
    }

    /// The card's own heading, with the legend beside it until the two stop
    /// fitting on one line.
    @ViewBuilder
    private func heroHeader(investable: [ChartPoint]) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                heroLabel
                if !investable.isEmpty { chartLegend }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                heroLabel
                Spacer(minLength: 8)
                if !investable.isEmpty { chartLegend }
            }
        }
    }

    private var heroLabel: some View {
        Text("NET WORTH")
            .font(.caption.weight(.semibold))
            .kerning(1)
            .foregroundStyle(Theme.dim)
    }

    /// The figure the hero prints: the scrubbed day while a finger is on the
    /// chart, otherwise today's net worth.
    private var heroAmount: Double { scrubbed?.value ?? snapshot.netWorth }

    /// "$1.240 Million" with the currency symbol shrunk and raised, the way the
    /// Kubera dashboard and the Net Worth widget set it.
    ///
    /// At accessibility sizes it switches to compact notation ("$1.24M"). The
    /// long form there either wraps mid-figure or gets scaled back below the
    /// size the reader asked for; the unabbreviated number stays in
    /// `accessibilityValue`, so this abbreviates rather than withholds.
    private var heroValue: Text {
        let text = typeSize.isAccessibilitySize
            ? Format.money(heroAmount, currency: currency, masked: masked, compact: true)
            : Format.millions(heroAmount, currency: currency, masked: masked)
        // Monospaced digits on the figure itself: a proportional set jitters the
        // whole card's width as a scrub moves through the series.
        let figure = Font.system(size: heroSize, weight: .bold).monospacedDigit()
        guard let split = currencySymbolSplit(text) else {
            return Text(text).font(figure).kerning(-1)
        }
        return Text(split.symbol)
            .font(.system(size: heroSize * 0.55, weight: .bold))
            .baselineOffset(heroSize * 0.3)
            + Text(split.rest)
            .font(figure)
            .kerning(-1)
    }

    /// The sentence VoiceOver reads for the hero and its delta together. The
    /// amount is unabbreviated even when the figure on screen is compacted for a
    /// large type size — the compaction is a layout concession, not the number.
    private func heroReadout(_ points: [ChartPoint]) -> String {
        let amount = Format.money(heroAmount, currency: currency, masked: masked, compact: false)
        guard let change = heroChange(in: points) else {
            return "\(amount), updated \(Format.updatedAt(snapshot.updatedAt))"
        }
        guard change.amount != 0 else { return "\(amount), unchanged \(heroDeltaLabel)" }
        let direction = change.amount > 0 ? "up" : "down"
        let moved = Format.money(abs(change.amount), currency: currency, masked: masked, compact: false)
        return "\(amount), \(direction) \(moved), \(Format.percent(abs(change.percent), signed: false)), \(heroDeltaLabel)"
    }

    @ViewBuilder
    private func heroDelta(_ points: [ChartPoint]) -> some View {
        if let change = heroChange(in: points) {
            let favorable = OverviewChart.isFavorable(change.amount, metric: .asset)
            let tail = Text(heroDeltaLabel)
                .font(.footnote)
                .foregroundStyle(Theme.dim)

            Group {
                if typeSize.isAccessibilitySize {
                    // One figure per line: at these sizes the row cannot hold a
                    // signed amount, a percent and the range's wording without
                    // scaling all three back down again.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            deltaGlyph(change.amount)
                            deltaAmount(change.amount)
                        }
                        deltaPercent(change.percent)
                        tail
                    }
                } else {
                    HStack(spacing: 6) {
                        deltaGlyph(change.amount)
                        deltaAmount(change.amount)
                        deltaPercent(change.percent)
                        tail
                    }
                }
            }
            // Exactly zero reads neutral. Green there would assert a gain that
            // did not happen.
            .foregroundStyle(change.amount == 0 ? Theme.dim : (favorable ? Theme.positive : Theme.negative))
        } else {
            Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }

    /// Direction as a glyph, so colour is never the only carrier. Absent at
    /// exactly zero: an arrow there claims a direction the figures do not show.
    @ViewBuilder
    private func deltaGlyph(_ amount: Double) -> some View {
        if amount != 0 {
            Text(amount < 0 ? "▼" : "▲")
                .font(.caption2.weight(.bold))
        }
    }

    private func deltaAmount(_ amount: Double) -> some View {
        Text(Format.money(amount, currency: currency, masked: masked, compact: false, signed: true))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: amount))
    }

    private func deltaPercent(_ percent: Double) -> some View {
        Text(Format.percent(percent))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: percent))
    }

    /// Both states measure from the **window's first** point, so touching the
    /// chart retargets the number without changing what it means.
    private func heroChange(in points: [ChartPoint]) -> (amount: Double, percent: Double)? {
        if let scrubbed {
            return OverviewChart.scrubChange(to: scrubbed, in: points)
        }
        return OverviewChart.change(in: points)
    }

    /// The sentence tail: the range's own wording at rest, the scrubbed date
    /// while dragging ("▲ $12,400 +1% by Jul 21").
    private var heroDeltaLabel: String {
        guard let scrubbed else { return range.deltaLabel }
        return "by \(Self.scrubDateFormatter.string(from: scrubbed.date))"
    }

    /// Investable as the hero's second figure, the way Kubera's dashboard card
    /// carries it — a step down in type, not a card of its own.
    @ViewBuilder
    private func investableLine(_ amount: Double) -> some View {
        let label = Text("INVESTABLE")
            .font(.caption2.weight(.semibold))
            .kerning(1)
            .foregroundStyle(Theme.dim)
        let figure = Text(Format.money(amount, currency: currency, masked: masked, compact: typeSize.isAccessibilitySize))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(Theme.text.opacity(0.85))

        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    label
                    figure
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label
                    figure
                }
            }
        }
        .contentTransition(.numericText(value: amount))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Investable")
        .accessibilityValue(Format.money(amount, currency: currency, masked: masked, compact: false))
    }

    /// Two dots and two words: the only way to tell the curves apart, and
    /// cheaper than Swift Charts' own legend, which would add a whole row.
    private var chartLegend: some View {
        HStack(spacing: 10) {
            legendEntry("Net worth", opacity: 1)
            legendEntry("Investable", opacity: investableLineOpacity)
        }
    }

    private func legendEntry(_ name: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.text.opacity(opacity))
                .frame(width: legendDotSize, height: legendDotSize)
            Text(name)
                .font(.caption2)
                .foregroundStyle(Theme.dim)
        }
    }

    private func chart(_ points: [ChartPoint], investable: [ChartPoint]) -> some View {
        // Each run is a stretch of history without a hole in it, drawn as its
        // own series so a multi-week gap breaks the line instead of being
        // interpolated across.
        let runs = OverviewChart.segments(points)
        let investableRuns = OverviewChart.segments(investable)

        // Each series is its own `@ChartContentBuilder` function rather than
        // being inlined here. Marks are deeply generic and the builder nests
        // their types, so four sibling series in one body put the type checker
        // past its time limit outright. An opaque `some ChartContent` return
        // resolves each one once, and the caller never reconsiders it.
        //
        // Order is the z-order: investable draws first so the net worth curve
        // stays the dominant line.
        return Chart {
            investableFill(investableRuns)
            investableLine(investableRuns)
            netWorthFill(runs)
            netWorthLine(runs)
        }
        // Monotone, not Catmull-Rom: Catmull-Rom overshoots and can draw a dip
        // below a low the portfolio never actually hit.
        //
        // One domain across both curves, so the gap between net worth and
        // investable is the real one.
        .chartYScale(domain: OverviewModules.yDomain([points, investable]))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                scrubLayer(proxy: proxy, geometry: geometry, points: points)
            }
        }
        .frame(height: 170)
        // A whole line redrawing across the card is exactly the large-area
        // movement Reduce Motion exists for; the new range still lands.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: range)
        .accessibilityLabel("Net worth over the \(range.deltaLabel)")
        .accessibilityChartDescriptor(NetWorthChartDescriptor(
            points: points,
            currency: currency,
            masked: masked,
            rangeLabel: range.deltaLabel
        ))
    }

    // MARK: - Chart series
    //
    // `series:` interpolates the run index because Swift Charts groups marks
    // into a line by that value: without it, the last point of one run would
    // connect to the first point of the next and draw a slope straight across a
    // gap in the history.
    //
    // Only the net worth line carries per-point accessibility labels. The fills
    // and the investable curve are hidden, so a VoiceOver swipe walks one curve
    // instead of crossing four overlapping series — the descriptor on the chart
    // covers the overall shape.

    @ChartContentBuilder
    private func investableFill(_ runs: [[ChartPoint]]) -> some ChartContent {
        ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
            ForEach(run) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Investable", point.value),
                    series: .value("Series", "investable-\(index)"),
                    stacking: .unstacked
                )
                .foregroundStyle(fillGradient(ceiling: investableFillCeiling))
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)
            }
        }
    }

    @ChartContentBuilder
    private func investableLine(_ runs: [[ChartPoint]]) -> some ChartContent {
        ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
            ForEach(run) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Investable", point.value),
                    series: .value("Series", "investable-line-\(index)")
                )
                .foregroundStyle(Theme.text.opacity(investableLineOpacity))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)
            }
        }
    }

    @ChartContentBuilder
    private func netWorthFill(_ runs: [[ChartPoint]]) -> some ChartContent {
        ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
            ForEach(run) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Net worth", point.value),
                    series: .value("Series", "networth-\(index)"),
                    stacking: .unstacked
                )
                .foregroundStyle(fillGradient(ceiling: netWorthFillCeiling))
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)
            }
        }
    }

    @ChartContentBuilder
    private func netWorthLine(_ runs: [[ChartPoint]]) -> some ChartContent {
        ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
            ForEach(run) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Net worth", point.value),
                    series: .value("Series", "networth-line-\(index)")
                )
                .foregroundStyle(Theme.text)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(Self.endpointDateFormatter.string(from: point.date))
                .accessibilityValue(
                    Format.money(point.value, currency: currency, masked: masked, compact: false)
                )
            }
        }
    }

    /// Monochrome by design — this app has no brand hue, so the second series is
    /// the same ink at a lower opacity rather than a new color.
    private var investableLineOpacity: Double { colorScheme == .dark ? 0.45 : 0.35 }

    /// Light mode muddies at the dark-mode ceiling.
    private var netWorthFillCeiling: Double { colorScheme == .dark ? 0.18 : 0.12 }
    private var investableFillCeiling: Double { colorScheme == .dark ? 0.10 : 0.07 }

    private func fillGradient(ceiling: Double) -> LinearGradient {
        LinearGradient(
            colors: [Theme.text.opacity(ceiling), Theme.text.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The chart's only axis furniture: the window's first and last date.
    private func endpointLabels(_ points: [ChartPoint]) -> some View {
        HStack {
            Text(Self.endpointDateFormatter.string(from: points[0].date))
            Spacer(minLength: 8)
            Text(Self.endpointDateFormatter.string(from: points[points.count - 1].date))
        }
        .font(.caption2)
        .foregroundStyle(Theme.dim)
    }

    /// Shown only in place of a chart that has nothing to draw, so it explains
    /// an absence rather than annotating real data. Which absence it is matters:
    /// an empty window with pills below it is a different instruction from a
    /// history that hasn't loaded.
    private var emptyChartNote: some View {
        Text(
            netWorthSeries.count >= 2
                ? "No history in this window yet. Try a longer range."
                : "Not enough history yet. Growth fills in as Kubera's history loads."
        )
        .font(.footnote)
        .foregroundStyle(Theme.dim)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One glass slab with plain pills inside it, rather than six glass buttons:
    /// a single sampling surface can't produce glass-on-glass, and the selected
    /// pill stays a solid `Theme.text` capsule so the selection reads without
    /// depending on translucency in either appearance.
    ///
    /// Six pills do not fit one row at accessibility sizes, so they fall into two
    /// columns rather than scrolling — a scrolling pill row hides ranges behind
    /// an edge, and the range control is how this screen is read.
    @ViewBuilder
    private var rangePills: some View {
        if typeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(ChartRange.allCases) { rangePill($0) }
            }
            .padding(3)
            .controlGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            HStack(spacing: 4) {
                ForEach(ChartRange.allCases) { rangePill($0) }
            }
            .padding(3)
            .controlGlass(in: Capsule())
        }
    }

    private func rangePill(_ option: ChartRange) -> some View {
        let active = option == range
        return Button {
            selectionHaptics.selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                range = option
                // A held readout from the old window would be a date the new one
                // may not contain.
                scrubbed = nil
            }
        } label: {
            Text(option.label)
                .font(.caption.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(active ? Theme.background : Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, pillVerticalPadding)
                .background(active ? Theme.text : .clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // "1W" spoken as letters says nothing; the range's own wording does.
        .accessibilityLabel(option.deltaLabel)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Scrubbing

    /// The scrub's whole surface: an invisible hit area over the plot, the rule
    /// and dot marking the held point, and the tooltip.
    @ViewBuilder
    private func scrubLayer(proxy: ChartProxy, geometry: GeometryProxy, points: [ChartPoint]) -> some View {
        let plot = plotRect(proxy: proxy, geometry: geometry)

        ZStack(alignment: .topLeading) {
            // The hit area is the whole overlay rather than just the plot, so a
            // finger near the chart's edge still reads.
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())

            if let scrubbed,
               let offsetX = proxy.position(forX: scrubbed.date),
               let offsetY = proxy.position(forY: scrubbed.value) {
                let x = plot.minX + offsetX

                Rectangle()
                    .fill(Theme.text.opacity(0.35))
                    .frame(width: 1, height: plot.height)
                    .position(x: x, y: plot.midY)

                // Pinned to the top of the plot rather than floating above the
                // dot: it keeps the one glass surface here from ever reaching
                // down to the glass pill row, and it stops the bubble from
                // jumping vertically as the curve rises and falls.
                scrubTooltip(scrubbed)
                    .position(
                        x: plot.minX + OverviewChart.tooltipCenter(
                            near: offsetX,
                            tooltipWidth: scrubTooltipWidth,
                            plotWidth: plot.width
                        ),
                        y: plot.minY + 14
                    )

                // Drawn last, so it stays visible where the curve peaks into the
                // tooltip's band — the bubble would otherwise swallow the marker
                // at exactly the point most worth pointing at. Card-colored halo,
                // so the dot reads as a dot over the 2pt line it sits on.
                ZStack {
                    Circle().fill(Theme.card).frame(width: 13, height: 13)
                    Circle().fill(Theme.text).frame(width: 7, height: 7)
                }
                .position(x: x, y: plot.minY + offsetY)
            }
        }
        // Simultaneous, not exclusive: an exclusive `DragGesture` claims the
        // touch the instant it lands and the page stops scrolling anywhere over
        // the chart. Running alongside the `ScrollView`'s own pan lets both see
        // the drag, and `OverviewChart.intent` decides which one acts on it.
        .simultaneousGesture(scrubGesture(proxy: proxy, plot: plot, points: points))
    }

    /// Swift Charts reports positions relative to the plot area, so the touch
    /// has to be moved into the same space. Falls back to the whole overlay when
    /// the plot anchor is unavailable, which is only off by the axis inset — and
    /// both axes are hidden here.
    private func plotRect(proxy: ChartProxy, geometry: GeometryProxy) -> CGRect {
        guard let anchor = proxy.plotFrame else {
            return CGRect(origin: .zero, size: geometry.size)
        }
        return geometry[anchor]
    }

    private func scrubTooltip(_ point: ChartPoint) -> some View {
        HStack(spacing: 6) {
            Text(Self.scrubDateFormatter.string(from: point.date))
                .foregroundStyle(Theme.dim)
            // Masked under privacy mode like every other amount; the date is
            // not, because a date leaks nothing.
            Text(Format.money(point.value, currency: currency, masked: masked, compact: false))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: scrubTooltipWidth)
        // Tinted, unlike the pill row: this one floats over the curve and its
        // gradient fill, and bare glass over that is unreadable.
        .controlGlass(in: Capsule(), tint: Theme.card)
    }

    private func scrubGesture(proxy: ChartProxy, plot: CGRect, points: [ChartPoint]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A `minimumDistance: 0` drag opens with a zero translation, so
                // this is where a new gesture announces itself — and it is the
                // only reset that survives the `ScrollView` cancelling the
                // previous drag without ever calling `onEnded`, which would
                // otherwise leave a readout stuck on screen and scrubbing wedged
                // off for good.
                if value.translation == .zero {
                    scrubIntent = .undecided
                    scrubbed = nil
                }

                if scrubIntent == .undecided {
                    let intent = OverviewChart.intent(
                        dx: value.translation.width,
                        dy: value.translation.height
                    )
                    guard intent != .undecided else { return }
                    scrubIntent = intent
                    if intent == .scrub { engageHaptics.impactOccurred(intensity: 0.5) }
                }

                guard scrubIntent == .scrub else { return }
                scrub(toX: value.location.x, proxy: proxy, plot: plot, points: points)
            }
            .onEnded { _ in endScrub() }
    }

    private func scrub(toX x: CGFloat, proxy: ChartProxy, plot: CGRect, points: [ChartPoint]) {
        guard OverviewChart.isScrubbable(points) else { return }

        let offsetX = x - plot.minX
        let date = proxy.value(atX: offsetX, as: Date.self)
            ?? OverviewChart.date(
                atFraction: plot.width > 0 ? offsetX / plot.width : 0,
                in: points
            )
        guard let date, let point = OverviewChart.nearest(to: date, in: points) else { return }
        guard point != scrubbed else { return }

        scrubbed = point
        tick()
    }

    /// One tick per data point crossed, and never faster than 30 a second: an
    /// ALL window can hold thousands of points, so a fast drag crosses dozens
    /// per frame and an unlimited generator turns that into a continuous buzz
    /// that reads as the phone malfunctioning.
    private func tick() {
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= 1.0 / 30 else { return }
        lastTick = now
        selectionHaptics.selectionChanged()
    }

    private func endScrub() {
        scrubIntent = .undecided
        guard scrubbed != nil else { return }
        // Animated on release but not during the drag: the hero has to track
        // the finger exactly while it moves, and only the spring back to today's
        // figure should read as motion.
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { scrubbed = nil }
    }

    // MARK: - Assets / debts

    private var statPair: some View {
        pairLayout {
            // Both cards lead to their own side's screen now that the payload's
            // `## Debts` table is parsed. Each waits for the rows it would show:
            // before the fetch lands there is nothing behind the card but an
            // empty state, and a card that answers a tap with "nothing here" is
            // worse than one that does not answer.
            statLink(.assets) {
                statCard("ASSETS", value: snapshot.assetTotal, series: assetSeries, metric: .asset)
            }
            statLink(.debts) {
                statCard("DEBTS", value: snapshot.debtTotal, series: debtSeries, metric: .debt)
            }
        }
    }

    /// Wraps a stat card in the tap that opens its side, when that side has rows
    /// to show. The detail fetch is decoration everywhere else on this screen;
    /// here it decides whether a tap target exists at all.
    ///
    /// No sheet is named: a card stands for the whole side, so it asks for the
    /// tab and leaves whatever sheet the reader last chose there.
    @ViewBuilder
    private func statLink(
        _ side: PortfolioSide,
        @ViewBuilder card: () -> some View
    ) -> some View {
        if detail?.rows(side).isEmpty == false {
            Button {
                store.showBook(side)
            } label: {
                card()
            }
            .buttonStyle(.plain)
            // The card's four elements — the figure and the two trend rows —
            // merge into one link announcement here. That is the trade a
            // whole-card link makes: keeping them separate would need the link
            // to become an accessibility container, which leaves nothing for
            // VoiceOver to activate. Nothing is lost, it is read in one pass
            // instead of four.
            .accessibilityHint("Opens the \(side.title.lowercased()) details")
        } else {
            card()
        }
    }

    /// Two cards abreast, stacked at accessibility sizes: half the screen width
    /// cannot hold a currency figure there without scaling it back below the size
    /// the reader asked for.
    private var pairLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// The 1 DAY and 1 YEAR lines are fixed windows, like Kubera's dashboard —
    /// they don't follow the chart's range pill, and they're computed from this
    /// metric's own history rather than borrowed from the net worth trend.
    private func statCard(
        _ label: String,
        value: Double,
        series: [ChartPoint],
        metric: OverviewChart.Metric
    ) -> some View {
        let trend = OverviewModules.trend(in: series, current: value, now: Date(), calendar: .current)
        // One unit for this card's two rows: per-value compaction put "+$1,348"
        // directly above "+$281K", and a column whose notation changes partway
        // down has to be re-read row by row. Assets and Debts are separate
        // columns of figures and need not agree with each other.
        //
        // Compacted whatever the compact-numbers preference says, unlike the
        // composition and holdings columns: these cards are half the screen
        // wide, and an exact six-figure change cannot share a line with its
        // percent.
        let unit = sharedTrendUnit([trend.day?.amount, trend.year?.amount].compactMap { $0 })

        return Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: masked, compact: typeSize.isAccessibilitySize))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityValue(Format.money(value, currency: currency, masked: masked, compact: false))

                VStack(alignment: .leading, spacing: 2) {
                    trendRow("1 DAY", trend.day, metric: metric, unit: unit)
                    trendRow("1 YEAR", trend.year, metric: metric, unit: unit)
                }
                .padding(.top, 2)
            }
        }
    }

    /// `Format.unit(spanning:)`, stepped back down until the card's smallest row
    /// can still say something.
    ///
    /// A day's move is two or three orders of magnitude under a year's, which is
    /// a wider spread than a composition column ever sees: taking the unit from
    /// the largest alone, a card whose year row is in millions rounds its day row
    /// to "$0.01M", or to "$0.00M", which claims nothing moved. Stepping the
    /// whole card down to thousands costs the year row the M suffix ("+$2410K")
    /// and keeps both rows in one notation, which is the trade `Format.unit`
    /// already makes inside a column.
    ///
    /// Zeros are excluded: a flat day cannot constrain a unit, and it renders as
    /// a plain "$0" rather than in the card's unit anyway.
    private func sharedTrendUnit(_ amounts: [Double]) -> Format.Unit {
        let spanning = Format.unit(spanning: amounts, compact: true)
        guard spanning != .exact,
              let smallest = amounts.map(abs).filter({ $0 > 0 }).min()
        else { return spanning }

        // Down to thousands and no further. A quiet day of $38 against a year of
        // $281K would otherwise drag the card back to exact and print
        // "+$281,400", which is wider than the ragged pair this all replaced —
        // the largest row is six figures by the time `Format.unit` compacts at
        // all, and spelling it out is width the row does not have.
        //
        // A tenth of the unit is the floor for two significant figures at the two
        // decimal places `Format.money` gives a compacted figure.
        let steps: [Format.Unit] = [.billions, .millions, .thousands]
        return steps.first { $0.divisor <= spanning.divisor && smallest >= $0.divisor / 10 } ?? .thousands
    }

    /// One "1 DAY  +$1.35K  +0.08%" line, the same shape at every magnitude: a
    /// card whose height depends on the reader's own numbers cannot be lined up
    /// against the card beside it, and a label optically centred against a
    /// two-line block on one row and a one-line block on the next is worse than
    /// either. An unknown change prints an em dash rather than a zero: a log
    /// that doesn't reach back a year has no answer, and "0%" would claim the
    /// portfolio stood still.
    @ViewBuilder
    private func trendRow(
        _ label: String,
        _ change: OverviewModules.Change?,
        metric: OverviewChart.Metric,
        unit: Format.Unit
    ) -> some View {
        let title = Text(label)
            .font(.caption2.weight(.semibold))
            .kerning(0.5)
            .foregroundStyle(Theme.dim)

        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    trendFigures(change, metric: metric, unit: unit, stacked: true)
                }
            } else {
                HStack(spacing: 4) {
                    title
                        .frame(width: trendLabelWidth, alignment: .leading)
                    trendFigures(change, metric: metric, unit: unit, stacked: false)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `stacked` is the accessibility-size form, where the figures get a line
    /// each unconditionally. Below that they always share one line — the shared
    /// unit and the dropped arrow bought the width for it.
    @ViewBuilder
    private func trendFigures(
        _ change: OverviewModules.Change?,
        metric: OverviewChart.Metric,
        unit: Format.Unit,
        stacked: Bool
    ) -> some View {
        Group {
            if let change {
                // Favorability, not sign: a shrinking debt is good news and
                // renders green. Exactly zero is neither, so it renders neutral.
                let favorable = OverviewChart.isFavorable(change.amount, metric: metric)
                let color = Theme.change(change.amount, isFavorable: favorable)

                if stacked {
                    VStack(alignment: .leading, spacing: 1) {
                        amount(change, unit: unit, color: color)
                        percent(change, color: color)
                    }
                } else {
                    // The slack sits between the two figures rather than after
                    // them, which puts the percents of all four rows across the
                    // two cards in one column.
                    HStack(spacing: 0) {
                        amount(change, unit: unit, color: color)
                        Spacer(minLength: 6)
                        percent(change, color: color)
                    }
                }
            } else {
                Text("—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .accessibilityLabel("not available")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The signed change. No arrow: the explicit + or − already carries the
    /// direction for a reader who cannot see the colour, and the glyph plus its
    /// gap was most of the width the row needed to hold the percent on the same
    /// line. `.fixedSize` and `.lineLimit(1)` keep the figure whole — broken
    /// across lines it reads as two numbers ("+$1,34" / "8").
    ///
    /// The label carries the uncompacted figure so VoiceOver still reads the
    /// exact amount the compacted glyphs stand in for.
    private func amount(
        _ change: OverviewModules.Change,
        unit: Format.Unit,
        color: Color
    ) -> some View {
        // The one row allowed out of the card's unit: a figure too small to
        // register in it would print "$0.00K", which claims nothing moved on a
        // day something did. Below a hundredth of the unit it says so exactly
        // instead. A flat day lands here too and prints a plain "$0", which
        // needs no unit.
        let resolved: Format.Unit = abs(change.amount) < unit.divisor / 100 ? .exact : unit

        return Text(Format.money(change.amount, currency: currency, masked: masked, unit: resolved, signed: true))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: change.amount))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .accessibilityLabel(
                Format.money(change.amount, currency: currency, masked: masked, compact: false, signed: true)
            )
    }

    /// Unparenthesised — two characters the row cannot spare, and the weight
    /// contrast against the amount already separates them. This is the figure
    /// that scales rather than the amount: on the narrowest device a percentage
    /// in the thousands is the only thing that can overrun the row, and the
    /// amount is the one that has to stay exact.
    @ViewBuilder
    private func percent(_ change: OverviewModules.Change, color: Color) -> some View {
        if let percent = change.percent {
            Text(Format.percent(percent))
                .font(.caption2)
                .monospacedDigit()
                .contentTransition(.numericText(value: percent))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(color)
        }
    }

    // MARK: - Cash on hand / tax estimate

    /// Cash and the tax estimate, both straight from the MCP detail fetch. Each
    /// hides itself when its field is nil, and the row collapses to one
    /// full-width card when only one of the two is knowable — an empty slot
    /// would be worse than no slot.
    @ViewBuilder
    private var balancePair: some View {
        let cash = detail?.cashOnHand
        let tax = detail?.estimatedTax

        if cash != nil || tax != nil {
            pairLayout {
                if let cash {
                    balanceCard("CASH ON HAND", value: cash, caption: cashCaption(cash))
                }
                if let tax {
                    // A modelled estimate, not a fact, so the caption says what
                    // it is modelled on rather than letting the number stand
                    // alone.
                    balanceCard("TAX ESTIMATE", value: tax, caption: "on unrealized gains")
                }
            }
            .padding(.top, 12)
        }
    }

    private func balanceCard(_ label: String, value: Double, caption: String?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: masked, compact: typeSize.isAccessibilitySize))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityValue(Format.money(value, currency: currency, masked: masked, compact: false))

                // The caption wraps rather than shrinking — it is a sentence, and
                // the blank placeholder only has to hold one line's height.
                Text(caption ?? " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    /// An absolute cash number says little without the denominator, so the
    /// caption is its share of net worth — and stays absent when net worth is
    /// not positive rather than dividing into it.
    private func cashCaption(_ cash: Double) -> String? {
        guard snapshot.netWorth > 0 else { return nil }
        return "\(Format.percent(cash / snapshot.netWorth * 100, signed: false)) of net worth"
    }

    // MARK: - Still unavailable
    //
    // "YOUR CLUB" peer percentile is the one module from Kubera's dashboard this
    // screen still leaves out: it comes from a session-authenticated endpoint
    // that neither an API key nor the MCP token reaches. The spec puts it out of
    // scope, and an empty slot would be worse than no slot.
    //
    // The Sankey is no longer among them: "Asset flow" above is the real thing,
    // drawn from `detail.assets` with the same four stages Kubera's web app
    // shows. See `SankeyView` for why it is allowed to be wider than the card.

    // MARK: - CAGR • YTD

    /// One line of the growth block. Both figures are optional: YTD needs the
    /// series to reach into last year, CAGR needs a full year of span.
    private struct GrowthRow: Identifiable {
        let id: String
        let label: String
        let ytd: Double?
        let cagr: Double?

        var isEmpty: Bool { ytd == nil && cagr == nil }
    }

    private var growthRows: [GrowthRow] {
        let now = Date()
        var rows: [GrowthRow] = [
            GrowthRow(
                id: "networth",
                label: "Net worth",
                ytd: OverviewModules.ytdPercent(
                    in: netWorthSeries,
                    current: snapshot.netWorth,
                    now: now,
                    calendar: .current
                ),
                cagr: OverviewModules.cagrPercent(in: netWorthSeries)
            ),
        ]
        if !investableSeries.isEmpty {
            rows.append(GrowthRow(
                id: "investable",
                label: "Investable",
                // Investable has no live figure on the snapshot, so its own
                // latest point is the current value — and only when that point
                // is fresh, so YTD never measures to a months-old figure.
                ytd: OverviewModules.ytdPercent(
                    in: investableSeries,
                    current: investableNow,
                    now: now,
                    calendar: .current
                ),
                cagr: OverviewModules.cagrPercent(in: investableSeries)
            ))
        }
        return rows.filter { !$0.isEmpty }
    }

    private var comps: [OverviewModules.Comp] {
        OverviewModules.comps(store.comps)
    }

    private var growthCard: some View {
        let rows = growthRows
        // The column only earns its header when something in it is knowable.
        let showsCAGR = rows.contains { $0.cagr != nil }

        return Card {
            VStack(alignment: .leading, spacing: 8) {
                if !rows.isEmpty {
                    // No column header at accessibility sizes: the rows below
                    // label each figure inline there, and a header over columns
                    // that no longer exist would point at nothing.
                    if !typeSize.isAccessibilitySize {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Text("YTD")
                                .frame(width: ytdColumnWidth, alignment: .trailing)
                            if showsCAGR {
                                Text("CAGR")
                                    .frame(width: cagrColumnWidth, alignment: .trailing)
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .kerning(0.5)
                        .foregroundStyle(Theme.dim)
                    }

                    ForEach(rows) { row in
                        growthRow(row, showsCAGR: showsCAGR)
                    }
                }

                if !comps.isEmpty {
                    // The comparison is the point, so the benchmarks sit inside
                    // the same card as your own numbers.
                    if !rows.isEmpty {
                        RowDivider()
                            .padding(.vertical, 2)
                    }
                    compsRow
                }
            }
        }
    }

    @ViewBuilder
    private func growthRow(_ row: GrowthRow, showsCAGR: Bool) -> some View {
        let name = Text(row.label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        // YTD is a change, so it carries direction.
        let ytd = Text(row.ytd.map { Format.percent($0) } ?? "—")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(percentColor(row.ytd))
        // CAGR stays neutral — it's a rate, not a change.
        let cagr = Text(row.cagr.map { Format.percent($0, signed: false) } ?? "—")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(row.cagr == nil ? Theme.dim : Theme.text)

        if typeSize.isAccessibilitySize {
            // The columns become labelled lines. A three-column row at these
            // sizes leaves each figure a few characters wide.
            VStack(alignment: .leading, spacing: 2) {
                name
                growthFigure("YTD", ytd)
                    .contentTransition(.numericText(value: row.ytd ?? 0))
                if showsCAGR {
                    growthFigure("CAGR", cagr)
                        .contentTransition(.numericText(value: row.cagr ?? 0))
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                name
                Spacer(minLength: 0)
                ytd
                    .contentTransition(.numericText(value: row.ytd ?? 0))
                    .frame(width: ytdColumnWidth, alignment: .trailing)
                if showsCAGR {
                    cagr
                        .contentTransition(.numericText(value: row.cagr ?? 0))
                        .frame(width: cagrColumnWidth, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func growthFigure(_ label: String, _ figure: Text) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.dim)
            figure
        }
    }

    /// Benchmarks in dim, smaller type so your own numbers stay dominant.
    @ViewBuilder
    private var compsRow: some View {
        // Side by side at normal sizes, one per line at accessibility sizes —
        // three columns there leaves "S&P 500" three characters wide.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        layout {
            ForEach(comps) { comp in
                VStack(alignment: .leading, spacing: 2) {
                    Text(comp.name)
                        .font(.caption2.weight(.semibold))
                        .kerning(0.5)
                        .foregroundStyle(Theme.dim)
                    Text(Format.percent(comp.percent))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(percentColor(comp.percent))
                        .contentTransition(.numericText(value: comp.percent))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func percentColor(_ percent: Double?) -> Color {
        guard let percent, percent != 0 else { return Theme.dim }
        return percent > 0 ? Theme.positive : Theme.negative
    }

    // MARK: - Allocation

    private var allocationSegments: [OverviewChart.AllocationSegment] {
        OverviewChart.allocationSegments(snapshot.allocation)
    }

    private var allocationCard: some View {
        let segments = allocationSegments
        let total = segments.reduce(0) { $0 + $1.percent }

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { proxy in
                    let gaps = CGFloat(max(segments.count - 1, 0)) * 2
                    let track = max(proxy.size.width - gaps, 0)
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            Rectangle()
                                .fill(rampColor(index))
                                .frame(width: total > 0 ? track * segment.percent / total : 0)
                        }
                    }
                }
                .frame(height: allocationBarHeight)
                .clipShape(Capsule())
                // The bar restates the legend below it; two elements saying the
                // same thing is one too many.
                .accessibilityHidden(true)

                // One column at accessibility sizes: a two-column legend there
                // gives each class name about six characters.
                LazyVGrid(
                    columns: typeSize.isAccessibilitySize
                        ? [GridItem(.flexible(), alignment: .leading)]
                        : [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(rampColor(index))
                                .frame(width: allocationDotSize, height: allocationDotSize)
                            Text(segment.name)
                                .font(.footnote)
                                .foregroundStyle(Theme.text)
                            Text(Format.percent(segment.percent, signed: false))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.dim)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Neutral ramp, never the semantic pair — green and red mean direction of
    /// change, not category.
    private func rampColor(_ index: Int) -> Color {
        let steps: [Double] = [0.92, 0.74, 0.58, 0.44, 0.32, 0.22]
        return Theme.text.opacity(steps[min(index, steps.count - 1)])
    }

    // MARK: - Composition

    /// The Sankey's flow: sections into sheets, sheets into Assets, Assets out
    /// into net worth and debts.
    ///
    /// It no longer follows the composition card's sheet/section toggle, and
    /// must not: the toggle picks *one* of the two levels, and this diagram now
    /// shows both at once with the ribbons between them. Nothing is left for the
    /// toggle to change here. The Composition card keeps it — a list can only
    /// show one level at a time.
    ///
    /// The debt figure is the snapshot's, the same one the DEBTS card prints two
    /// blocks up. Note that the Assets node is the sum of the assets actually in
    /// the detail fetch rather than `snapshot.assetTotal`, because a Sankey's
    /// one claim is that its columns balance; if the two ever disagree it is the
    /// diagram that stays internally consistent, and the cards that carry the
    /// authoritative totals.
    private var assetFlow: Sankey.Flow {
        Sankey.assetFlow(from: detail?.assets ?? [], debtTotal: snapshot.debtTotal)
    }

    /// The diagram is wider than the card and slides sideways, so it bleeds past
    /// the card's padding and puts that padding back as its own content inset:
    /// at rest the labels line up with everything else on the screen, and a drag
    /// carries them out under the card's edge instead of clipping them mid-word.
    private var assetFlowCard: some View {
        Card {
            SankeyView(
                flow: assetFlow,
                currency: currency,
                masked: masked,
                compact: compactNumbers,
                contentInset: Self.cardInset,
                accessibilityTitle: "Asset flow"
            )
            .padding(.horizontal, -Self.cardInset)
        }
    }

    /// The sheet a tapped row should open on. The rule lives in `PortfolioBook`,
    /// where it can be tested; this is only the level the card is showing.
    private func sheetID(
        for group: OverviewModules.CompositionGroup,
        in book: PortfolioBook?
    ) -> String? {
        PortfolioBook.sheetID(forGroup: group.name, at: compositionLevel, resolvingSectionsIn: book)
    }

    private var compositionGroups: [OverviewModules.CompositionGroup] {
        OverviewModules.composition(detail?.assets ?? [], by: compositionLevel)
    }

    /// Offered only when both levels actually have labels to group by.
    private var offersLevelToggle: Bool {
        OverviewModules.CompositionLevel.allCases.allSatisfy { level in
            OverviewModules.isLabelled(OverviewModules.composition(detail?.assets ?? [], by: level))
        }
    }

    private var compositionCard: some View {
        let groups = compositionGroups
        let largest = groups.first?.value ?? 0
        // One unit for the whole column: per-value compaction put "$130K" two
        // rows above "$74,000", which cannot be scanned.
        let unit = Format.unit(spanning: groups.map(\.value), compact: compactNumbers)
        // Built once per render, and only at section level where a row's name
        // has to be resolved against the whole book. A scrub re-renders this
        // card on every touch move, and one book per row per frame is work a
        // large portfolio would feel.
        let book = compositionLevel == .section ? PortfolioBook(.assets, in: detail) : nil

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                if offersLevelToggle {
                    levelPills
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    compositionRow(
                        index: index,
                        group: group,
                        largest: largest,
                        unit: unit,
                        sheetID: sheetID(for: group, in: book)
                    )
                }
            }
        }
    }

    private func compositionRow(
        index: Int,
        group: OverviewModules.CompositionGroup,
        largest: Double,
        unit: Format.Unit,
        sheetID: String?
    ) -> some View {
        // Scaled so the largest group fills the track, like the holdings rows —
        // scaled to 100% every bar but the first would read as empty.
        let fraction = largest > 0 ? group.value / largest : 0

        let name = Text(group.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        let amount = Text(Format.money(group.value, currency: currency, masked: masked, unit: unit))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
        // Name over value at accessibility sizes rather than label-left,
        // value-right: the two would otherwise collide mid-row.
        let heading = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        // A button that switches tabs rather than a link that pushes: pushing
        // put the assets screen inside the Overview's own stack, which left the
        // tab bar highlighting Overview while the reader looked at assets — and
        // made tapping the Overview tab from there do nothing at all, because
        // they had never left it.
        return Button {
            store.showBook(.assets, sheetID: sheetID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                heading {
                    name
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    amount
                        .contentTransition(.numericText(value: group.value))
                }

                HStack(spacing: 8) {
                    ShareBar(fraction: fraction, color: rampColor(index))
                    Text(Format.percent(group.percent, signed: false))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .frame(width: sharePercentWidth, alignment: .trailing)
                }
            }
            // The slack between the bar and the percent is part of the row, not
            // dead space beside it.
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the asset details")
        }
        // Plain, like every other tappable row in this app: the default style
        // tints the name and the amount, and no row here carries a chevron.
        .buttonStyle(.plain)
    }

    private var levelPills: some View {
        // Two pills, sized to their labels with the row's slack trailing them.
        // At accessibility sizes they stack instead, where two content-sized
        // pills would overrun the card.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        return layout {
            ForEach(OverviewModules.CompositionLevel.allCases) { option in
                let active = option == compositionLevel
                Button {
                    selectionHaptics.selectionChanged()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { compositionLevel = option }
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.semibold))
                        .kerning(0.5)
                        .foregroundStyle(active ? Theme.background : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(active ? Theme.text : .clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }

    // MARK: - Top holdings

    private var holdingsCard: some View {
        let ranked = Array(snapshot.topHoldings.sorted { $0.value > $1.value }.prefix(5))
        let largest = ranked.first?.value ?? 0

        // Shared across the column for the same reason as the composition rows.
        // Compaction here also follows the type size: at accessibility sizes the
        // row has far less width for the figure, so it compacts even when the
        // preference is off.
        let unit = Format.unit(
            spanning: ranked.map(\.value),
            compact: compactNumbers || typeSize.isAccessibilitySize
        )

        return Card(padding: .cardRows) {
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { index, holding in
                    if index > 0 { RowDivider() }
                    holdingRow(index: index, holding: holding, largest: largest, unit: unit)
                }
            }
        }
    }

    private func holdingRow(
        index: Int,
        holding: Holding,
        largest: Double,
        unit: Format.Unit
    ) -> some View {
        // The bar is share of net worth scaled so the largest holding fills the
        // track; scaled to 100% every row would look nearly empty.
        let share = snapshot.netWorth > 0 ? holding.value / snapshot.netWorth * 100 : 0
        let fraction = largest > 0 ? holding.value / largest : 0

        let name = Text(holding.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        let sheet = (holding.sheet?.isEmpty == false ? holding.sheet : nil).map {
            Text($0)
                .font(.caption2)
                .foregroundStyle(Theme.dim)
        }
        let amount = Text(Format.money(holding.value, currency: currency, masked: masked, unit: unit))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)

        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .frame(width: rankWidth, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                if typeSize.isAccessibilitySize {
                    // Name, sheet and amount each get their own line: three
                    // items on one row leaves the amount a couple of digits.
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        if let sheet { sheet }
                        amount
                            .contentTransition(.numericText(value: holding.value))
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        name
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let sheet {
                            sheet.lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        amount
                            .contentTransition(.numericText(value: holding.value))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                HStack(spacing: 8) {
                    ShareBar(fraction: fraction)
                    Text(Format.percent(share, signed: false))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .frame(width: sharePercentWidth, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 12)
        // One statement per holding: rank, name, amount, share. As five elements
        // it reads as a list of fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index + 1). \(holding.name)")
        .accessibilityValue(
            "\(Format.money(holding.value, currency: currency, masked: masked, compact: false)), "
                + "\(Format.percent(share, signed: false)) of net worth"
        )
    }

    // MARK: - Footer

    private var footer: some View {
        // The history fetch outcome is a diagnostic, not dashboard content — it
        // belongs in Settings, where it can be acted on.
        Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
            .font(.caption)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - Data

    private func reload() async {
        loadHistory()
        errorMessage = nil
        do {
            try await store.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        // The refresh folds today's snapshot into the log and backfills any
        // server series, so re-read after it lands.
        loadHistory()
    }

    private func loadHistory() {
        let series = store.history
        // Animated so a refresh that moves the figures reads as the numbers
        // changing rather than as the screen being replaced.
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            netWorthSeries = OverviewChart.points(from: series, calendar: .current)
            assetSeries = OverviewChart.points(from: series, calendar: .current) { $0.assetTotal }
            debtSeries = OverviewChart.points(from: series, calendar: .current) { $0.debtTotal }
            investableSeries = OverviewModules.investableSeries(from: series, calendar: .current)
        }
    }

    // MARK: - Formatting helpers

    /// Cached: the endpoint labels render twice per layout and the scrub tooltip
    /// re-renders on every touch move, and building a `DateFormatter` per call
    /// there is the kind of allocation a drag can feel.
    private static let endpointDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// "Jul 21" — no year, because the window already prints its own endpoints
    /// and the delta's tail has to fit beside a signed amount and a percent.
    private static let scrubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// Everything ahead of the first digit is the currency symbol ("$", "kr ").
    /// Nil for a masked value, which has no symbol to split off.
    private func currencySymbolSplit(_ text: String) -> (symbol: String, rest: String)? {
        guard let firstDigit = text.firstIndex(where: { $0.isNumber }),
              firstDigit != text.startIndex else {
            return nil
        }
        return (String(text[..<firstDigit]), String(text[firstDigit...]))
    }
}

/// Share-of-portfolio track for a holding row. Stays visible in privacy mode —
/// it encodes a relative share, not an amount.
private struct ShareBar: View {
    let fraction: Double
    var color: Color = Theme.text.opacity(0.75)

    /// Grows with the percent label beside it: a 6pt hairline next to text at
    /// AX5 reads as a rule rather than a bar.
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        // The percent beside it says the same thing in words.
        .accessibilityHidden(true)
    }
}

/// Hands VoiceOver the Audio Graph experience over the visible window: the
/// shape of the curve as tones, and a stepped walk through the points.
///
/// Without this the chart is an unlabelled image — the most common
/// accessibility failure in finance apps. Belongs beside the rest of the chart
/// arithmetic in `Shared/OverviewChart.swift`; it lives here only because that
/// file was owned by another change when this landed.
///
/// Amounts follow privacy mode like everything else on screen. The tones still
/// carry the shape, which is what the drawn curve gives a sighted reader under
/// the same setting.
private struct NetWorthChartDescriptor: AXChartDescriptorRepresentable {
    let points: [ChartPoint]
    let currency: String
    let masked: Bool
    let rangeLabel: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = points.map(\.date.timeIntervalSince1970)
        let values = points.map(\.value)
        // A descriptor with an inverted or empty range is a crash rather than a
        // degraded experience, so both axes fall back to a unit range.
        let xRange = (dates.min() ?? 0) ... max(dates.max() ?? 1, (dates.min() ?? 0) + 1)
        let yRange = (values.min() ?? 0) ... max(values.max() ?? 1, (values.min() ?? 0) + 1)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: xRange,
            gridlinePositions: []
        ) { value in
            Self.dateFormatter.string(from: Date(timeIntervalSince1970: value))
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Net worth",
            range: yRange,
            gridlinePositions: []
        ) { value in
            Format.money(value, currency: currency, masked: masked, compact: false)
        }

        let series = AXDataSeriesDescriptor(
            name: "Net worth",
            isContinuous: true,
            dataPoints: points.map { point in
                AXDataPoint(
                    x: point.date.timeIntervalSince1970,
                    y: point.value,
                    additionalValues: [],
                    label: Self.dateFormatter.string(from: point.date)
                )
            }
        )

        return AXChartDescriptor(
            title: "Net worth over the \(rangeLabel)",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.series = makeChartDescriptor().series
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

#if DEBUG
// `AppStore()` reads whatever is cached on the previewing device; with nothing
// stored, `snapshot` falls back to `.sample`, so the layout is exercised either
// way and no invented figure is committed here.
#Preview("Overview") {
    OverviewView()
        .environment(AppStore())
}

#Preview("Overview — dark") {
    OverviewView()
        .environment(AppStore())
        .preferredColorScheme(.dark)
}

#Preview("Overview — AX5") {
    OverviewView()
        .environment(AppStore())
        .environment(\.dynamicTypeSize, .accessibility5)
}

// The two underscored keys are read-only in a shipping build and settable only
// in previews. They stay inside `#if DEBUG` — they are private symbols and must
// not reach a submitted binary.
#Preview("Overview — AX5 + increased contrast") {
    OverviewView()
        .environment(AppStore())
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\._colorSchemeContrast, .increased)
        .environment(\._accessibilityDifferentiateWithoutColor, true)
}
#endif
