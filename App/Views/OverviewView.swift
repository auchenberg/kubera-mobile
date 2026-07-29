import Charts
import SwiftUI

/// The Overview screen: one hero number, the chart that reads it out, then
/// supporting stats. Phase 1 of `specs/overview-dashboard.md` — static chart,
/// plain capsule range pills, no scrubbing and no glass (both phase 2).
///
/// All arithmetic lives in `OverviewChart` so it can be unit tested; this file
/// is layout only.
struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var range: ChartRange = .month
    @State private var errorMessage: String?
    /// Parsed once per load rather than per render — each parse walks the whole
    /// series through a DateFormatter.
    @State private var netWorthSeries: [ChartPoint] = []
    @State private var assetSeries: [ChartPoint] = []
    @State private var debtSeries: [ChartPoint] = []
    @State private var historyNote: String?

    /// Falls back to the sample portfolio so the screen never renders empty —
    /// a signed-out or pre-first-fetch launch still shows the real layout.
    private var snapshot: PortfolioSnapshot { store.snapshot ?? .sample }
    private var currency: String { snapshot.currency }
    private var masked: Bool { store.settings.privacyMode }

    private var visiblePoints: [ChartPoint] {
        OverviewChart.filter(netWorthSeries, to: range, now: Date(), calendar: .current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

                    if !allocationSegments.isEmpty {
                        SectionTitle("Allocation")
                        allocationCard
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
            .navigationTitle("Overview")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    // MARK: - Hero + chart

    private var heroCard: some View {
        Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("NET WORTH")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                heroValue
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.text)
                    .padding(.top, 2)

                heroDelta
                    .padding(.top, 4)

                if visiblePoints.count >= 2 {
                    chart(visiblePoints)
                        .padding(.top, 14)
                    endpointLabels(visiblePoints)
                        .padding(.top, 6)
                    rangePills
                        .padding(.top, 12)
                } else {
                    emptyChartNote
                        .padding(.top, 16)
                }
            }
        }
    }

    /// "$1.240 Million" with the currency symbol shrunk and raised, the way the
    /// Kubera dashboard and the Net Worth widget set it.
    private var heroValue: Text {
        let size: CGFloat = 40
        let text = Format.millions(snapshot.netWorth, currency: currency, masked: masked)
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
    private var heroDelta: some View {
        if let change = OverviewChart.change(in: visiblePoints) {
            let favorable = OverviewChart.isFavorable(change.amount, metric: .asset)
            HStack(spacing: 6) {
                Text(change.amount < 0 ? "▼" : "▲")
                    .font(.system(size: 11, weight: .bold))
                Text(Format.money(change.amount, currency: currency, masked: masked, compact: false, signed: true))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(Format.percent(change.percent))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(range.deltaLabel)
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

    private func chart(_ points: [ChartPoint]) -> some View {
        // Each run is a stretch of history without a hole in it, drawn as its
        // own series so a multi-week gap breaks the line instead of being
        // interpolated across.
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
        // below a low the portfolio never actually hit.
        .chartYScale(domain: OverviewChart.yDomain(points))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 170)
        .animation(.easeInOut(duration: 0.3), value: range)
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
    private func endpointLabels(_ points: [ChartPoint]) -> some View {
        HStack {
            Text(shortDate(points[0].date))
            Spacer(minLength: 8)
            Text(shortDate(points[points.count - 1].date))
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.dim)
    }

    private var emptyChartNote: some View {
        Text(historyNote ?? "Growth history needs a Kubera MCP token.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rangePills: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases) { option in
                let active = option == range
                Button {
                    withAnimation(.snappy(duration: 0.25)) { range = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(active ? Theme.background : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(active ? Theme.text : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Assets / debts
    //
    // Investable is missing on purpose: `PortfolioSnapshot` carries no
    // investable figure, and deriving one from the allocation percentages would
    // be a guess dressed up as a number. It arrives with the phase 3 fetch,
    // together with cash on hand.

    private var statPair: some View {
        HStack(spacing: 12) {
            statCard("ASSETS", value: snapshot.assetTotal, series: assetSeries, metric: .asset)
            statCard("DEBTS", value: snapshot.debtTotal, series: debtSeries, metric: .debt)
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

                Text(Format.money(value, currency: currency, masked: masked, compact: false))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let change {
                    // Favorability, not sign: a shrinking debt is good news and
                    // renders green.
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
        VStack(spacing: 4) {
            Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            // Only worth showing next to the chart; repeating it here when the
            // chart is hidden would say the same thing twice.
            if let historyNote, visiblePoints.count >= 2 {
                Text(historyNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
        }
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
        netWorthSeries = OverviewChart.points(from: series, calendar: .current)
        assetSeries = OverviewChart.points(from: series, calendar: .current) { $0.assetTotal }
        debtSeries = OverviewChart.points(from: series, calendar: .current) { $0.debtTotal }
        historyNote = SharedStore.historyStatus()
    }

    // MARK: - Formatting helpers

    /// Everything ahead of the first digit is the currency symbol ("$", "kr ").
    /// Nil for a masked value, which has no symbol to split off.
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

/// Share-of-portfolio track for a holding row. Stays visible in privacy mode —
/// it encodes a relative share, not an amount.
private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(Theme.text.opacity(0.75))
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
