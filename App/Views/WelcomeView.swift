import Charts
import SwiftUI
import WidgetKit

/// Step 1 of the first run: the app itself, running on a synthetic portfolio,
/// before asking for anything. A new user sees the dashboard and the actual
/// widget views rather than a list of claims about them.
///
/// Reachable only while `AppStore.credentials` is nil, so there is no "has seen
/// welcome" flag to persist — the absence of credentials *is* the condition.
///
/// Everything on screen comes from `DemoData` and is labelled as sample data.
/// The demo never touches the App Group caches, so none of these numbers can
/// leak into a widget as if they were the user's own.
struct WelcomeView: View {
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The hero keeps a point size rather than a text style because its currency
    /// symbol is set at 55% of it and lifted by 30% of it, and a text style hands
    /// back no number to take a fraction of. Same treatment as `OverviewView`,
    /// since this screen is a preview of that one.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var pillVerticalPadding: CGFloat = 7

    /// 1Y by default: the widest window that is dense enough to read, and the
    /// one that shows the demo's growth. The pills are live — the range control
    /// is part of what's being demonstrated.
    @State private var range: ChartRange = .year

    private let snapshot = DemoData.snapshot
    private var currency: String { snapshot.currency }

    private var visiblePoints: [ChartPoint] {
        OverviewChart.filter(DemoData.netWorthPoints, to: range, now: Date(), calendar: .current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                heroCard
                    .padding(.top, 24)

                statPair
                    .padding(.top, 12)

                detailPair
                    .padding(.top, 12)

                SectionTitle("On your Home Screen")
                widgetStrip

                ActionButton(title: "Connect your Kubera account", action: onContinue)
                    .padding(.top, 28)

                reassurance
                    .padding(.top, 16)

                footnote
                    .padding(.top, 14)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
        }
        .background(Theme.background)
        .softTopScrollEdge()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kubera Mobile")
                .font(.system(.largeTitle, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Theme.text)

            Text("Your net worth, on your Home Screen.")
                .font(.body)
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Dashboard preview
    //
    // Deliberately the same layout as the Overview screen — this is a preview of
    // that screen, not a marketing rendition of it. `OverviewView` is a separate
    // file that owns its own copies; the shared arithmetic lives in
    // `OverviewChart`, so the two cannot disagree about a number.

    private var heroCard: some View {
        Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader

                VStack(alignment: .leading, spacing: 4) {
                    heroValue
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.text)

                    heroDelta
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sample net worth")
                .accessibilityValue(heroReadout)

                chart(visiblePoints)
                    .padding(.top, 14)
                endpointLabels(visiblePoints)
                    .padding(.top, 6)
                rangePills
                    .padding(.top, 12)
            }
        }
    }

    /// The card's own heading, with the sample marker beside it until the two
    /// stop fitting on one line.
    @ViewBuilder
    private var heroHeader: some View {
        let label = Text("NET WORTH")
            .font(.caption.weight(.semibold))
            .kerning(1)
            .foregroundStyle(Theme.dim)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                label
                samplePill
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 8)
                samplePill
            }
        }
    }

    /// Small, quiet and always visible: enough that nobody reads the demo as
    /// their own portfolio, not so loud that it fights the numbers.
    private var samplePill: some View {
        Text("SAMPLE DATA")
            .font(.caption2.weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.text.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
    }

    /// "$1.240 Million" with the currency symbol shrunk and raised, the way the
    /// Kubera dashboard and the Net Worth widget set it.
    ///
    /// At accessibility sizes it switches to compact notation ("$1.24M"), with
    /// the unabbreviated number in `accessibilityValue` — the same bargain
    /// `OverviewView` strikes, so the demo shows what the real screen does.
    private var heroValue: Text {
        let text = typeSize.isAccessibilitySize
            ? Format.money(snapshot.netWorth, currency: currency, masked: false, compact: true)
            : Format.millions(snapshot.netWorth, currency: currency, masked: false)
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

    /// The sentence VoiceOver reads for the hero and its delta together, with the
    /// amount unabbreviated whatever the type size does to the figure on screen.
    private var heroReadout: String {
        let amount = Format.money(snapshot.netWorth, currency: currency, masked: false, compact: false)
        guard let change = OverviewChart.change(in: visiblePoints) else { return amount }
        guard change.amount != 0 else { return "\(amount), unchanged \(range.deltaLabel)" }
        let direction = change.amount > 0 ? "up" : "down"
        let moved = Format.money(abs(change.amount), currency: currency, masked: false, compact: false)
        return "\(amount), \(direction) \(moved), \(Format.percent(abs(change.percent), signed: false)), \(range.deltaLabel)"
    }

    @ViewBuilder
    private var heroDelta: some View {
        if let change = OverviewChart.change(in: visiblePoints) {
            let favorable = OverviewChart.isFavorable(change.amount, metric: .asset)
            let amount = Text(Format.money(change.amount, currency: currency, masked: false, compact: false, signed: true))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            let percent = Text(Format.percent(change.percent))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            let tail = Text(range.deltaLabel)
                .font(.footnote)
                .foregroundStyle(Theme.dim)

            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            deltaGlyph(change.amount)
                            amount
                        }
                        percent
                        tail
                    }
                } else {
                    HStack(spacing: 6) {
                        deltaGlyph(change.amount)
                        amount
                        percent
                        tail
                    }
                }
            }
            // Exactly zero reads neutral. Green there would assert a gain that
            // did not happen.
            .foregroundStyle(change.amount == 0 ? Theme.dim : (favorable ? Theme.positive : Theme.negative))
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

    private func chart(_ points: [ChartPoint]) -> some View {
        // Each run is a stretch of history without a hole in it. The demo series
        // has no gaps, but going through the same helper keeps this drawing the
        // code path the real chart uses.
        let runs = OverviewChart.segments(points)

        return Chart {
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Net worth", point.value),
                        series: .value("Segment", index),
                        stacking: .unstacked
                    )
                    .foregroundStyle(fillGradient)
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                ForEach(run) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Net worth", point.value),
                        series: .value("Segment", index)
                    )
                    .foregroundStyle(Theme.text)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        // Monotone, not Catmull-Rom: Catmull-Rom overshoots and can draw a dip
        // below a low the series never actually hit.
        .chartYScale(domain: OverviewChart.yDomain(points))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 150)
        // A whole line redrawing across the card is exactly the large-area
        // movement Reduce Motion exists for; the new range still lands.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: range)
        .accessibilityLabel("Sample net worth over the \(range.deltaLabel)")
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            // Light mode muddies at the dark-mode ceiling.
            colors: [Theme.text.opacity(colorScheme == .dark ? 0.18 : 0.12), Theme.text.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The chart's only axis furniture: the window's first and last date.
    @ViewBuilder
    private func endpointLabels(_ points: [ChartPoint]) -> some View {
        if let first = points.first, let last = points.last {
            HStack {
                Text(shortDate(first.date))
                Spacer(minLength: 8)
                Text(shortDate(last.date))
            }
            .font(.caption2)
            .foregroundStyle(Theme.dim)
        }
    }

    /// Six pills do not fit one row at accessibility sizes, so they fall into two
    /// columns rather than scrolling — a scrolling pill row hides ranges behind
    /// an edge, and the range control is part of what this screen demonstrates.
    @ViewBuilder
    private var rangePills: some View {
        if typeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(ChartRange.allCases) { rangePill($0) }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(ChartRange.allCases) { rangePill($0) }
            }
        }
    }

    private func rangePill(_ option: ChartRange) -> some View {
        let active = option == range
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { range = option }
        } label: {
            Text(option.label)
                .font(.caption.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(active ? Theme.background : Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, pillVerticalPadding)
                .background(active ? Theme.text : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        // "1W" spoken as letters says nothing; the range's own wording does.
        .accessibilityLabel(option.deltaLabel)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Assets / debts

    private var statPair: some View {
        pairLayout {
            statCard("ASSETS", value: snapshot.assetTotal, series: DemoData.assetPoints, metric: .asset)
            statCard("DEBTS", value: snapshot.debtTotal, series: DemoData.debtPoints, metric: .debt)
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

    /// The two figures Kubera serves only over MCP. Shown here because the demo
    /// has to advertise every module the signed-in Overview renders — a module
    /// missing from the demo reads as a missing feature.
    @ViewBuilder
    private var detailPair: some View {
        let detail = DemoData.detail
        if let cash = detail.cashOnHand, let tax = detail.estimatedTax {
            pairLayout {
                plainStatCard("CASH ON HAND", value: cash, note: "6% of net worth")
                plainStatCard("TAX ESTIMATE", value: tax, note: "on unrealized gains")
            }
        }
    }

    private func plainStatCard(_ label: String, value: Double, note: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: false, compact: typeSize.isAccessibilitySize))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityValue(Format.money(value, currency: currency, masked: false, compact: false))

                // Wraps rather than shrinking: it is a phrase, not a figure.
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statCard(
        _ label: String,
        value: Double,
        series: [ChartPoint],
        metric: OverviewChart.Metric
    ) -> some View {
        let change = OverviewChart.change(
            in: OverviewChart.filter(series, to: range, now: Date(), calendar: .current)
        )

        return Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: false, compact: false))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let change {
                    // Favorability, not sign: the demo's debt shrinks, and that
                    // is good news, so it reads green.
                    let favorable = OverviewChart.isFavorable(change.amount, metric: metric)
                    Text("\(change.amount < 0 ? "▼" : "▲") \(Format.percent(change.percent))")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(change.amount == 0 ? Theme.dim : (favorable ? Theme.positive : Theme.negative))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    // Holds the third line's height so the two cards in the row
                    // stay the same size when only one has a delta.
                    Text(" ")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Widget previews
    //
    // The real widget views from `Shared/WidgetViews.swift` at the real small
    // size, so this is what actually lands on the Home Screen rather than a
    // drawing of it. `family` is passed explicitly: `\.widgetFamily` is an
    // environment key only WidgetKit populates.

    private var widgetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                widgetCard {
                    NetWorthWidgetContent(
                        snapshot: snapshot,
                        trends: DemoData.trends,
                        settings: DemoData.settings,
                        family: .systemSmall
                    )
                }
                widgetCard {
                    CagrWidgetContent(
                        snapshot: snapshot,
                        trends: DemoData.trends,
                        comps: DemoData.comps,
                        settings: DemoData.settings,
                        family: .systemSmall
                    )
                }
                widgetCard {
                    AssetsDebtsWidgetContent(
                        snapshot: snapshot,
                        settings: DemoData.settings,
                        family: .systemSmall
                    )
                }
            }
            // Insets inside the scroll view rather than around it, so the strip
            // bleeds off the screen edge and reads as scrollable.
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -20)
    }

    /// A small widget is 158×158 in points, on the widget's own adaptive
    /// background, so the plate matches the Home Screen in both appearances.
    ///
    /// In light mode that background is the same shade as this screen's, so the
    /// plate is outlined and lifted on a shadow to keep its bounds legible —
    /// the treatment `widgetPreviewFrame` gives the previews in Widgets.
    private func widgetCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return content()
            .padding(16)
            .frame(width: 158, height: 158, alignment: .topLeading)
            .background(WidgetTheme.background)
            .clipShape(shape)
            .overlay(shape.strokeBorder(WidgetTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 8, y: 3)
    }

    // MARK: - Closing

    private var reassurance: some View {
        Text(
            """
            Access is read-only — nothing is ever written to your Kubera account. \
            Your keys stay in this device's Keychain, and there is no server in \
            between: the app talks to Kubera directly.
            """
        )
        .font(.system(size: 13))
        .lineSpacing(4)
        .foregroundStyle(Theme.dim)
    }

    private var footnote: some View {
        Text("The figures above are sample data. Connecting replaces them with your own portfolio.")
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(Theme.dim.opacity(0.8))
    }

    // MARK: - Formatting helpers

    /// Everything ahead of the first digit is the currency symbol ("$", "kr ").
    private func currencySymbolSplit(_ text: String) -> (symbol: String, rest: String)? {
        guard let firstDigit = text.firstIndex(where: { $0.isNumber }),
              firstDigit != text.startIndex else {
            return nil
        }
        return (String(text[..<firstDigit]), String(text[firstDigit...]))
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview("Welcome") {
    WelcomeView(onContinue: {})
}

#Preview("Welcome — dark") {
    WelcomeView(onContinue: {})
        .preferredColorScheme(.dark)
}
