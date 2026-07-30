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
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greeting
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    if let errorMessage {
                        Card {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.negative)
                        }
                        .padding(.bottom, 12)
                    }

                    heroCard
                        .padding(.bottom, 12)

                    statPair

                    balancePair

                    if !growthRows.isEmpty || !comps.isEmpty {
                        // Benchmarks alone are not your CAGR, so the heading
                        // stops claiming to be when your own rows are missing.
                        SectionTitle(growthRows.isEmpty ? "Market" : "CAGR • YTD")
                        growthCard
                    }

                    if !allocationSegments.isEmpty {
                        SectionTitle("Allocation")
                        allocationCard
                    }

                    if !compositionGroups.isEmpty {
                        SectionTitle("Composition")
                        compositionCard
                    }

                    if !snapshot.topHoldings.isEmpty {
                        SectionTitle("Top holdings")
                        holdingsCard
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
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
        }
    }

    // MARK: - Greeting

    /// The screen's heading: "Hej, Kenneth", with a quiet marker when the
    /// greeting is a hello the reader may not know.
    private var greeting: some View {
        let phrase = Greeting.phrase(for: greetingDate)

        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Greeting.line(for: greetingDate, name: greetingName))
                .font(.system(size: 26, weight: .semibold))
                .kerning(-0.3)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let note = phrase.note {
                greetingNoteMarker(note)
            }
            Spacer(minLength: 0)
        }
    }

    /// The account's own name when the profile fetch has landed, else the
    /// portfolio's. `Greeting.firstName` already treats the generic portfolio
    /// names as nameless, so this hands over whichever it has without checking.
    private var greetingName: String? {
        store.profile?.name ?? store.snapshot?.portfolioName
    }

    /// A footnote, not a badge: `Theme.dim` and no tint, because anything
    /// colored beside a greeting reads as something being wrong.
    private func greetingNoteMarker(_ note: String) -> some View {
        Button {
            showsGreetingNote = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What this greeting means")
        .popover(isPresented: $showsGreetingNote) {
            Text(note)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(14)
                // Without this a popover becomes a sheet on a phone, which is a
                // whole modal for one sentence.
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Hero + chart

    private var heroCard: some View {
        // Windowed once per render and handed down: the scrub reads these on
        // every touch move, and re-filtering the whole series per subview would
        // do it several times a frame.
        let points = visiblePoints
        let investable = visibleInvestablePoints

        return Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("NET WORTH")
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(Theme.dim)
                    Spacer(minLength: 8)
                    if !investable.isEmpty {
                        chartLegend
                    }
                }

                heroValue
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: heroAmount))
                    .padding(.top, 2)

                heroDelta(points)
                    .padding(.top, 4)

                if let investableNow {
                    investableLine(investableNow)
                        .padding(.top, 10)
                }

                if points.count >= 2 {
                    chart(points, investable: investable)
                        .padding(.top, 14)
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

    /// The figure the hero prints: the scrubbed day while a finger is on the
    /// chart, otherwise today's net worth.
    private var heroAmount: Double { scrubbed?.value ?? snapshot.netWorth }

    /// "$1.240 Million" with the currency symbol shrunk and raised, the way the
    /// Kubera dashboard and the Net Worth widget set it.
    private var heroValue: Text {
        let size: CGFloat = 40
        let text = Format.millions(heroAmount, currency: currency, masked: masked)
        guard let split = currencySymbolSplit(text) else {
            return Text(text).font(.system(size: size, weight: .bold)).kerning(-1)
        }
        return Text(split.symbol)
            .font(.system(size: size * 0.55, weight: .bold))
            .baselineOffset(size * 0.3)
            + Text(split.rest)
            .font(.system(size: size, weight: .bold))
            .kerning(-1)
    }

    @ViewBuilder
    private func heroDelta(_ points: [ChartPoint]) -> some View {
        if let change = heroChange(in: points) {
            let favorable = OverviewChart.isFavorable(change.amount, metric: .asset)
            HStack(spacing: 6) {
                Text(change.amount < 0 ? "▼" : "▲")
                    .font(.system(size: 11, weight: .bold))
                Text(Format.money(change.amount, currency: currency, masked: masked, compact: false, signed: true))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: change.amount))
                Text(Format.percent(change.percent))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: change.percent))
                Text(heroDeltaLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
            }
            .foregroundStyle(change.amount == 0 ? Theme.dim : (favorable ? Theme.positive : Theme.negative))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
        }
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
    private func investableLine(_ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("INVESTABLE")
                .font(.system(size: 11, weight: .semibold))
                .kerning(1)
                .foregroundStyle(Theme.dim)
            Text(Format.money(amount, currency: currency, masked: masked, compact: false))
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text.opacity(0.85))
                .contentTransition(.numericText(value: amount))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
        }
    }

    private func chart(_ points: [ChartPoint], investable: [ChartPoint]) -> some View {
        // Each run is a stretch of history without a hole in it, drawn as its
        // own series so a multi-week gap breaks the line instead of being
        // interpolated across.
        let runs = OverviewChart.segments(points)
        let investableRuns = OverviewChart.segments(investable)

        return Chart {
            // Investable first, so the net worth curve draws over it and stays
            // the dominant line.
            ForEach(Array(investableRuns.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Investable", point.value),
                        series: .value("Series", "investable-\(index)"),
                        stacking: .unstacked
                    )
                    .foregroundStyle(fillGradient(ceiling: investableFillCeiling))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(investableRuns.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Investable", point.value),
                        series: .value("Series", "investable-line-\(index)")
                    )
                    .foregroundStyle(Theme.text.opacity(investableLineOpacity))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
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
                }
            }
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
                }
            }
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
        .animation(.easeInOut(duration: 0.3), value: range)
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
        .font(.system(size: 11))
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
        .font(.system(size: 13))
        .foregroundStyle(Theme.dim)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One glass slab with plain pills inside it, rather than six glass buttons:
    /// a single sampling surface can't produce glass-on-glass, and the selected
    /// pill stays a solid `Theme.text` capsule so the selection reads without
    /// depending on translucency in either appearance.
    private var rangePills: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { option in
                let active = option == range
                Button {
                    selectionHaptics.selectionChanged()
                    withAnimation(.snappy(duration: 0.25)) {
                        range = option
                        // A held readout from the old window would be a date the
                        // new one may not contain.
                        scrubbed = nil
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(active ? Theme.background : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(active ? Theme.text : .clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .controlGlass(in: Capsule())
    }

    // MARK: - Scrubbing

    /// Fixed rather than measured: a bubble that resizes as the digits change
    /// jitters under the finger, and a constant width means the clamp against
    /// the plot edges is a constant too.
    private static let scrubTooltipWidth: CGFloat = 148

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
                            tooltipWidth: Self.scrubTooltipWidth,
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
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: Self.scrubTooltipWidth)
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
        withAnimation(.snappy(duration: 0.25)) { scrubbed = nil }
    }

    // MARK: - Assets / debts

    private var statPair: some View {
        HStack(spacing: 12) {
            statCard("ASSETS", value: snapshot.assetTotal, series: assetSeries, metric: .asset)
            statCard("DEBTS", value: snapshot.debtTotal, series: debtSeries, metric: .debt)
        }
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

        return Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: masked, compact: false))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                VStack(alignment: .leading, spacing: 2) {
                    trendRow("1 DAY", trend.day, metric: metric)
                    trendRow("1 YEAR", trend.year, metric: metric)
                }
                .padding(.top, 2)
            }
        }
    }

    /// One "1 DAY ▲ $19,100 (+1.5%)" line. An unknown change prints an em dash
    /// rather than a zero: a log that doesn't reach back a year has no answer,
    /// and "0%" would claim the portfolio stood still.
    private func trendRow(
        _ label: String,
        _ change: OverviewModules.Change?,
        metric: OverviewChart.Metric
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.dim)
                .frame(width: 42, alignment: .leading)

            if let change {
                // Favorability, not sign: a shrinking debt is good news and
                // renders green.
                let favorable = OverviewChart.isFavorable(change.amount, metric: metric)
                let color = change.amount == 0 ? Theme.dim : (favorable ? Theme.positive : Theme.negative)
                Text(change.amount < 0 ? "▼" : "▲")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(Format.money(abs(change.amount), currency: currency, masked: masked, compact: true))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: change.amount))
                if let percent = change.percent {
                    Text("(\(Format.percent(percent)))")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText(value: percent))
                }
            } else {
                Text("—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
            HStack(spacing: 12) {
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
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: masked, compact: false))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(caption ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
    // The Sankey is replaced rather than omitted — see the Composition module,
    // which tells the same "where is the money" story from `detail.assets`
    // without the custom Path drawing a faithful flow diagram would need.

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
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text("YTD")
                            .frame(width: 76, alignment: .trailing)
                        if showsCAGR {
                            Text("CAGR")
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.dim)

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

    private func growthRow(_ row: GrowthRow, showsCAGR: Bool) -> some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            // YTD is a change, so it carries direction.
            Text(row.ytd.map { Format.percent($0) } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(percentColor(row.ytd))
                .contentTransition(.numericText(value: row.ytd ?? 0))
                .frame(width: 76, alignment: .trailing)

            if showsCAGR {
                // CAGR stays neutral — it's a rate, not a change.
                Text(row.cagr.map { Format.percent($0, signed: false) } ?? "—")
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(row.cagr == nil ? Theme.dim : Theme.text)
                    .contentTransition(.numericText(value: row.cagr ?? 0))
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .lineLimit(1)
    }

    /// Benchmarks in dim, smaller type so your own numbers stay dominant.
    private var compsRow: some View {
        HStack(spacing: 8) {
            ForEach(comps) { comp in
                VStack(alignment: .leading, spacing: 2) {
                    Text(comp.name)
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(Format.percent(comp.percent))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(percentColor(comp.percent))
                        .contentTransition(.numericText(value: comp.percent))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(height: 12)
                .clipShape(Capsule())

                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(rampColor(index))
                                .frame(width: 8, height: 8)
                            Text(segment.name)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(Format.percent(segment.percent, signed: false))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
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

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                if offersLevelToggle {
                    levelPills
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    compositionRow(index: index, group: group, largest: largest)
                }
            }
        }
    }

    private func compositionRow(
        index: Int,
        group: OverviewModules.CompositionGroup,
        largest: Double
    ) -> some View {
        // Scaled so the largest group fills the track, like the holdings rows —
        // scaled to 100% every bar but the first would read as empty.
        let fraction = largest > 0 ? group.value / largest : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(Format.money(group.value, currency: currency, masked: masked, compact: true))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: group.value))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ShareBar(fraction: fraction, color: rampColor(index))
                Text(Format.percent(group.percent, signed: false))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private var levelPills: some View {
        HStack(spacing: 4) {
            ForEach(OverviewModules.CompositionLevel.allCases) { option in
                let active = option == compositionLevel
                Button {
                    selectionHaptics.selectionChanged()
                    withAnimation(.snappy(duration: 0.25)) { compositionLevel = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(active ? Theme.background : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(active ? Theme.text : .clear)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Top holdings

    private var holdingsCard: some View {
        let ranked = Array(snapshot.topHoldings.sorted { $0.value > $1.value }.prefix(5))
        let largest = ranked.first?.value ?? 0

        return Card(padding: .cardRows) {
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { index, holding in
                    if index > 0 { RowDivider() }
                    holdingRow(index: index, holding: holding, largest: largest)
                }
            }
        }
    }

    private func holdingRow(index: Int, holding: Holding, largest: Double) -> some View {
        // The bar is share of net worth scaled so the largest holding fills the
        // track; scaled to 100% every row would look nearly empty.
        let share = snapshot.netWorth > 0 ? holding.value / snapshot.netWorth * 100 : 0
        let fraction = largest > 0 ? holding.value / largest : 0

        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(holding.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let sheet = holding.sheet, !sheet.isEmpty {
                        Text(sheet)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Format.money(holding.value, currency: currency, masked: masked, compact: false))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: holding.value))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                HStack(spacing: 8) {
                    ShareBar(fraction: fraction)
                    Text(Format.percent(share, signed: false))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        // The history fetch outcome is a diagnostic, not dashboard content — it
        // belongs in Settings, where it can be acted on.
        Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
            .font(.system(size: 12))
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
        // The merged server + on-device series; the same one the trends and the
        // widgets read, so the chart can't disagree with them.
        let series = SharedStore.localHistory()
        // Animated so a refresh that moves the figures reads as the numbers
        // changing rather than as the screen being replaced.
        withAnimation(.snappy(duration: 0.25)) {
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
