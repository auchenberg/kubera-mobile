import SwiftUI

/// The Sankey flow: the sections of each sheet gathering into their sheets, the
/// sheets into one Assets bar, and Assets splitting back out into net worth and
/// debts.
///
/// All of the arithmetic is in `Shared/Sankey.swift`; this view scales the unit
/// box to whatever it is given, draws the ribbons, and decides where the labels
/// live. It renders nothing when the flow has nothing to break down — see
/// `Sankey.Flow.isMeaningful` — so a caller should gate its section heading on
/// that rather than on this view's presence.
///
/// **Why it is wider than the phone.** The old version was two columns because
/// 393 points is not enough for three, and it said so. That was a constraint of
/// the card, not of the data: Kubera's own web diagram carries four stages, and
/// the stage this app was dropping — a sheet as both a destination and a source
/// — is the one thing a flow diagram says that two stacked bar lists don't. So
/// the drawing now happens on a fixed canvas about twice the card's width inside
/// a horizontal `ScrollView`, and the phone slides along it. Free dragging, not
/// paging: the diagram is one continuous object and snapping it into pages would
/// invent boundaries the data doesn't have.
///
/// **Where the labels sit.** The first column's labels go in a gutter to the
/// left of its bars, right-aligned against them; the last column's go in a
/// gutter on the right; everything in between is labelled just left of its own
/// bar, over the ribbons arriving at it. That is the reference layout, and the
/// two gutters are also what makes the canvas wide — they are reserved outside
/// the unit box the maths works in, so no label can ever be drawn over a node
/// bar. Labels over ribbons stay `Theme.text` over a ribbon capped at 30%
/// opacity, which holds ~9:1 in light mode and ~6.8:1 in dark; Kubera's own
/// diagram draws white-on-pastel and the bottom half of it is unreadable.
struct SankeyView: View {
    /// Built by the caller — grouping and folding are decided by the data, and
    /// this view only knows how tall it ended up. See
    /// `Sankey.assetFlow(from:debtTotal:)`.
    let flow: Sankey.Flow
    let currency: String
    var masked: Bool = false
    var compact: Bool = true
    /// How far the drawing sits inside its own leading and trailing edges when
    /// at rest — the enclosing card's inner padding. The scroll view bleeds to
    /// the card's edges so a drag slides the leftmost labels out of sight
    /// smoothly instead of clipping them against the padding.
    var contentInset: CGFloat = 0
    /// What VoiceOver calls the whole diagram. The caller knows what the flow
    /// was grouped by; this view only knows the node names.
    var accessibilityTitle: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    @ScaledMetric(relativeTo: .footnote) private var labelledHeight: CGFloat = 300
    /// Roughly one line of `.caption` plus the air around it: the pitch a leaf
    /// row needs before two labels touch. The canvas grows downwards to hold
    /// the leaf column at this pitch, which is what keeps `Sankey`'s twelve-leaf
    /// cap legible.
    @ScaledMetric(relativeTo: .footnote) private var rowPitch: CGFloat = 26
    /// The floor handed to the layout, in points. `Sankey.layout` lowers it per
    /// column when a column has too many nodes to honour it — see
    /// `Sankey.maximumFloorShare` — so this is the floor a *sparse* column gets.
    @ScaledMetric(relativeTo: .footnote) private var nodeMinimum: CGFloat = 24
    /// A cap, not a reserved column, for the labels drawn over the ribbons; the
    /// two outer gutters really are reserved and are this wide. Long names
    /// truncate rather than reaching into the fan where ribbons are crossing.
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 156
    @ScaledMetric(relativeTo: .footnote) private var labelGap: CGFloat = 8
    /// The narrowest a ribbon gap may be before a cubic reads as a diagonal
    /// rather than as a curve. This, times the number of gaps, is most of the
    /// canvas width.
    @ScaledMetric(relativeTo: .footnote) private var ribbonGap: CGFloat = 110
    @ScaledMetric(relativeTo: .footnote) private var swatchSize: CGFloat = 10

    /// The diagram's size once the labels have moved out of it. Deliberately
    /// *not* `@ScaledMetric`: at accessibility sizes these would be multiplied
    /// by two and a half, and a 750pt-tall picture with no text in it is not
    /// what someone asking for larger text wants.
    private static let unlabelledHeight: CGFloat = 200
    private static let unlabelledNodeMinimum: CGFloat = 12
    private static let unlabelledRibbonGap: CGFloat = 90

    // MARK: - Body

    var body: some View {
        if flow.isMeaningful {
            // Placed once here rather than inside each part of the view: the
            // height it is placed against is known before anything is drawn, and
            // laying the same flow out twice is how a legend ends up disagreeing
            // with the diagram beside it.
            let diagram = Sankey.layout(flow, geometry: geometry)
            let unit = Format.unit(spanning: diagram.nodes.map(\.value), compact: compact)

            VStack(alignment: .leading, spacing: 12) {
                // At accessibility sizes nothing can sit inside the diagram, so
                // the Assets node gets a heading row and the sheets the legend.
                if usesLegend, let trunk = diagram.trunk {
                    header(name: trunk.name, value: trunk.value)
                }
                scroller(diagram, unit: unit)
                    .frame(height: diagramHeight)
                if usesLegend {
                    legend(diagram, unit: unit)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityTitle ?? "Asset flow")
        }
    }

    /// At accessibility sizes a node's name no longer fits beside its bar — a
    /// single word is taller than the bar it belongs to — so the labels move out
    /// into a stacked legend below and the diagram keeps only its shapes. The
    /// ribbons still carry the proportions, and the luminance ramp ties each
    /// legend row to its bar, largest first.
    private var usesLegend: Bool { typeSize.isAccessibilitySize }

    /// The tallest column decides the height: the leaf column is the one that
    /// runs out of room, and a row per leaf at `rowPitch` is what its labels
    /// need. `Sankey.defaultMaximumLeaves` bounds this, so the card cannot grow
    /// without limit.
    private var diagramHeight: CGFloat {
        guard !usesLegend else { return Self.unlabelledHeight }
        let rows = flow.stages.map(\.items.count).max() ?? 0
        return max(labelledHeight, CGFloat(rows) * rowPitch)
    }

    private var geometry: Sankey.Geometry {
        let floor = usesLegend ? Self.unlabelledNodeMinimum : nodeMinimum
        return Sankey.Geometry(minimumThickness: Double(floor / diagramHeight))
    }

    // MARK: - The wide canvas

    /// The gutter each of the two outer label columns is reserved, outside the
    /// unit box the maths works in. Zero once the labels have left for the
    /// legend: an empty gutter is 150 points of nothing to drag past.
    private var gutter: CGFloat { usesLegend ? 0 : labelWidth + labelGap }

    /// The width the diagram is drawn at, before the card gets a say: the two
    /// label gutters plus a ribbon gap per column boundary, grossed up for the
    /// node bars that sit inside that span. Four columns at the default metrics
    /// comes to about 710 points, a little over twice a phone card's width.
    ///
    /// A card wider than this — iPad, or landscape — gets the extra width
    /// instead, and then nothing scrolls, because there is nothing overflowing.
    /// That is also what happens at accessibility sizes: with the gutters gone
    /// and a fixed ribbon gap, the shapes fit a phone card again and there is
    /// nothing left to drag. The gap is fixed there for the same reason the
    /// height is — scaling a picture with no text in it by two and a half is not
    /// what someone asking for larger text wants.
    private func designWidth(columns: Int) -> CGFloat {
        let span = usesLegend ? Self.unlabelledRibbonGap : ribbonGap
        let gaps = CGFloat(max(columns - 1, 1)) * span
        let bars = min(Sankey.Geometry().bandWidth * Double(columns), 0.5)
        return gutter * 2 + gaps / CGFloat(1 - bars)
    }

    private func scroller(_ diagram: Sankey.Diagram, unit: Format.Unit) -> some View {
        GeometryReader { proxy in
            let available = proxy.size.width - contentInset * 2
            let width = max(available, designWidth(columns: diagram.columns.count))

            ScrollView(.horizontal, showsIndicators: false) {
                canvas(diagram, size: CGSize(width: width, height: proxy.size.height), unit: unit)
                    .frame(width: width, height: proxy.size.height)
                    .padding(.horizontal, contentInset)
            }
            // No bounce when the whole diagram already fits: a card that rubber
            // bands with nothing to reveal reads as a broken scroll view.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    /// The drawing plus its labels. The unit box the maths works in is mapped
    /// into `plot` — the canvas minus the two label gutters — so a label can
    /// never be drawn on top of a node bar.
    private func canvas(_ diagram: Sankey.Diagram, size: CGSize, unit: Format.Unit) -> some View {
        let plot = CGRect(
            x: gutter,
            y: 0,
            width: max(size.width - gutter * 2, 1),
            height: size.height
        )

        return ZStack(alignment: .topLeading) {
            shapes(diagram, in: plot, canvas: size)
            if !usesLegend {
                labels(diagram, in: plot, unit: unit)
            }
        }
    }

    // MARK: - Shapes

    /// The drawing, hidden from VoiceOver as one piece: the labels beside it (or
    /// the legend below it) say everything it says, and two elements reading out
    /// the same node is one too many.
    private func shapes(_ diagram: Sankey.Diagram, in plot: CGRect, canvas: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(diagram.links) { link in
                ribbon(link, in: plot).fill(ribbonGradient(link, in: plot, canvas: canvas))
            }
            ForEach(diagram.nodes) { node in
                capsule(node.box, in: plot).fill(nodeColor(node.rank ?? 0))
            }
        }
        .accessibilityHidden(true)
    }

    /// The standard Sankey ribbon: two cubics whose control points both sit at
    /// the horizontal midpoint of the gap, so the curve leaves its node and
    /// arrives at the next horizontally instead of shearing into either.
    private func ribbon(_ link: Sankey.Link, in plot: CGRect) -> Path {
        let x0 = plot.minX + link.sourceX * plot.width
        let x1 = plot.minX + link.targetX * plot.width
        let cx = plot.minX + link.controlX * plot.width
        let sourceTop = plot.minY + link.sourceTop * plot.height
        let sourceBottom = plot.minY + link.sourceBottom * plot.height
        let targetTop = plot.minY + link.targetTop * plot.height
        let targetBottom = plot.minY + link.targetBottom * plot.height

        var path = Path()
        path.move(to: CGPoint(x: x0, y: sourceTop))
        path.addCurve(
            to: CGPoint(x: x1, y: targetTop),
            control1: CGPoint(x: cx, y: sourceTop),
            control2: CGPoint(x: cx, y: targetTop)
        )
        path.addLine(to: CGPoint(x: x1, y: targetBottom))
        path.addCurve(
            to: CGPoint(x: x0, y: sourceBottom),
            control1: CGPoint(x: cx, y: targetBottom),
            control2: CGPoint(x: cx, y: sourceBottom)
        )
        path.closeSubpath()
        return path
    }

    /// Node bars are capsules, like the reference's: at this width a square end
    /// reads as a cut-off ribbon rather than as a cap.
    private func capsule(_ box: Sankey.Box, in plot: CGRect) -> Path {
        let frame = CGRect(
            x: plot.minX + box.x * plot.width,
            y: plot.minY + box.y * plot.height,
            width: box.width * plot.width,
            height: box.height * plot.height
        )
        guard frame.width > 0, frame.height > 0 else { return Path(frame) }
        return Path(roundedRect: frame, cornerRadius: min(frame.width, frame.height) / 2)
    }

    // MARK: - Labels

    /// First column in the left gutter, last column in the right one, everything
    /// between them tucked against the left of its own bar. The middle labels
    /// are the only ones that land on a ribbon, and they get whatever the gap
    /// they sit in can spare.
    @ViewBuilder
    private func labels(_ diagram: Sankey.Diagram, in plot: CGRect, unit: Format.Unit) -> some View {
        let last = diagram.columns.count - 1
        ForEach(Array(diagram.columns.enumerated()), id: \.offset) { index, column in
            let width = index == 0 || index == last
                ? labelWidth
                : min(labelWidth, max(gap(before: index, in: diagram, plot: plot) - labelGap * 2, 1))
            // Only the middle columns have to fit inside a ribbon gap, so only
            // they stack the amount under the name. The outer two have a whole
            // gutter and read better on one line.
            let stacked = index != 0 && index != last
            ForEach(column) { node in
                if index == last {
                    label(node, unit: unit, alignment: .leading, stacked: stacked)
                        .frame(width: width, alignment: .leading)
                        .position(
                            x: plot.minX + node.box.maxX * plot.width + labelGap + width / 2,
                            y: plot.minY + node.box.midY * plot.height
                        )
                } else {
                    label(node, unit: unit, alignment: .trailing, stacked: stacked)
                        .frame(width: width, alignment: .trailing)
                        .position(
                            x: plot.minX + node.box.x * plot.width - labelGap - width / 2,
                            y: plot.minY + node.box.midY * plot.height
                        )
                }
            }
        }
    }

    /// The points between one column's bars and the previous column's, which is
    /// all the room a label laid over the ribbons has.
    private func gap(before index: Int, in diagram: Sankey.Diagram, plot: CGRect) -> CGFloat {
        guard index > 0,
              let node = diagram.columns[index].first,
              let previous = diagram.columns[index - 1].first else { return labelWidth }
        return CGFloat(node.box.x - previous.box.maxX) * plot.width
    }

    /// Name and amount on one line where the gutter allows it — the wide canvas
    /// has the room the phone-only version didn't, and one line per node is what
    /// lets twelve leaves stack without their labels touching. Stacked, it is the
    /// two-line label this diagram has always used beside its bars.
    ///
    /// One line each way: a wrapped name would be taller than the bar it belongs
    /// to and the labels would start overlapping. The name shrinks before it
    /// truncates; the amount never does, because it is the figure being read.
    private func label(
        _ node: Sankey.Node,
        unit: Format.Unit,
        alignment: HorizontalAlignment,
        stacked: Bool
    ) -> some View {
        let name = Text(node.name)
            .font(.caption.weight(.semibold))
        let amount = Text(Format.money(node.value, currency: currency, masked: masked, unit: unit))
            .font(.caption2)
            .monospacedDigit()
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: alignment, spacing: 1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))

        return layout {
            if !stacked, alignment == .trailing { Spacer(minLength: 0) }
            name
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            amount
                .lineLimit(1)
                .layoutPriority(1)
            if !stacked, alignment == .leading { Spacer(minLength: 0) }
        }
        // Both parts in `Theme.text` rather than the amount in `Theme.dim`: over
        // a ribbon `dim` falls to about 1.9:1, which is the mistake that makes
        // the bottom half of the reference image unreadable. The legend below
        // sits on the card and can afford `dim`; this cannot.
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.name)
        .accessibilityValue(accessibilityValue(node, unit: unit))
    }

    // MARK: - Header and legend

    /// Names the trunk and states what it carries, which is the one figure every
    /// other node is a share of.
    private func header(name: String, value: Double) -> some View {
        let title = Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        let total = Text(Format.money(value, currency: currency, masked: masked, compact: compact))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)

        // Name over total at accessibility sizes; the two would otherwise
        // collide mid-row, the same way the composition rows do.
        let stack = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        return stack {
            title
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            total
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ diagram: Sankey.Diagram, unit: Format.Unit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(diagram.summaryColumn) { node in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // A rounded square rather than a dot: at these sizes it has
                    // to read as the same object as the bar it stands for.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(nodeColor(node.rank ?? 0))
                        .frame(width: swatchSize, height: swatchSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(amountText(node, unit: unit))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.dim)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(node.name)
                .accessibilityValue(accessibilityValue(node, unit: unit))
            }
        }
    }

    /// One unit across every node, the way the composition column does it:
    /// per-value compaction puts "$130K" two rows above "$74,000".
    private func amountText(_ node: Sankey.Node, unit: Format.Unit) -> String {
        let money = Format.money(node.value, currency: currency, masked: masked, unit: unit)
        return "\(money) · \(Format.percent(node.percent, signed: false))"
    }

    /// The exact share, spoken. The drawn bar is clamped to a minimum height and
    /// so is only approximately proportional; this figure never is. The share is
    /// of the whole flow, which every column sums to.
    private func accessibilityValue(_ node: Sankey.Node, unit: Format.Unit) -> String {
        let money = Format.money(node.value, currency: currency, masked: masked, unit: unit)
        return "\(money), \(Format.percent(node.percent, signed: false)) of the total"
    }

    // MARK: - Colour

    /// Monochrome by policy: green and red mean direction of change here, not
    /// category, so the nodes separate by luminance in value order instead. The
    /// darkest node in a column is the largest, which is also the reading order.
    /// The ramp restarts per column, so the single Assets bar takes the darkest
    /// tone and reads as the diagram's spine.
    private func nodeColor(_ rank: Int) -> Color {
        let steps: [Double] = contrast == .increased
            ? [1, 0.88, 0.76, 0.65, 0.55, 0.46]
            : [0.92, 0.74, 0.58, 0.44, 0.32, 0.22]
        return Theme.text.opacity(steps[min(max(rank, 0), steps.count - 1)])
    }

    /// Ribbons run at a fraction of their node's weight for two reasons: they
    /// cover most of the diagram's area, and — unlike in the reference — labels
    /// sit on top of them, so this ceiling is also the contrast budget. Raising
    /// it above 0.30 is what would make those labels unreadable.
    private func ribbonColor(_ rank: Int) -> Color {
        let steps: [Double] = contrast == .increased
            ? [0.42, 0.37, 0.32, 0.28, 0.24, 0.21]
            : [0.30, 0.25, 0.20, 0.16, 0.13, 0.10]
        return Theme.text.opacity(steps[min(max(rank, 0), steps.count - 1)])
    }

    /// Every ribbon is a wash from the tone of the node it leaves to the tone of
    /// the one it arrives at, which is the reference's category-to-category
    /// gradient rendered in the one palette this app has. It also makes the
    /// direction of travel visible in a diagram that no longer has a single
    /// trunk every ribbon starts from.
    ///
    /// The end points are given in the *canvas's* coordinates rather than as
    /// `.leading`/`.trailing`: a filled `Path` is a view the size of the whole
    /// canvas, so a leading-to-trailing gradient would spread each ribbon's wash
    /// over 700 points and show only the slice its own span happens to cross.
    /// Pinning the stops to the ribbon's two ends is what makes every ribbon
    /// complete its wash between its own two nodes.
    private func ribbonGradient(_ link: Sankey.Link, in plot: CGRect, canvas: CGSize) -> LinearGradient {
        let width = max(canvas.width, 1)
        return LinearGradient(
            colors: [ribbonColor(link.sourceRank), ribbonColor(link.rank)],
            startPoint: UnitPoint(x: (plot.minX + link.sourceX * plot.width) / width, y: 0.5),
            endPoint: UnitPoint(x: (plot.minX + link.targetX * plot.width) / width, y: 0.5)
        )
    }
}

#if DEBUG
private struct SankeyPreviewHost: View {
    var debtTotal: Double = DemoData.snapshot.debtTotal
    var assets: [PortfolioDetail.Asset] = DemoData.detail.assets

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Asset flow")
                Card {
                    SankeyView(
                        flow: Sankey.assetFlow(from: assets, debtTotal: debtTotal),
                        currency: DemoData.detail.currency ?? "USD",
                        contentInset: 16,
                        accessibilityTitle: "Asset flow"
                    )
                    // Bleeds to the card's edges so a drag can slide the gutter
                    // labels out of sight; `contentInset` puts them back where
                    // the card's padding would have at rest.
                    .padding(.horizontal, -16)
                }
            }
            // 20 to match the Overview screen's own inset, so the preview shows
            // the real width the diagram has to slide inside.
            .padding(.horizontal, 20)
        }
        .background(Theme.background)
    }
}

// Every figure below comes from `DemoData` — a synthetic ~$1.2M book. This
// repository is public.
#Preview("Sankey — assets, net worth, debts") {
    SankeyPreviewHost()
}

#Preview("Sankey — dark") {
    SankeyPreviewHost()
        .preferredColorScheme(.dark)
}

/// Debt-free: the outflow column disappears rather than drawing a net worth node
/// that would just repeat Assets.
#Preview("Sankey — no debts") {
    SankeyPreviewHost(debtTotal: 0)
}

/// Every asset unsectioned, so the leaf column collapses and the diagram is
/// sheets into Assets into the split.
#Preview("Sankey — no sections") {
    SankeyPreviewHost(assets: DemoData.detail.assets.map {
        PortfolioDetail.Asset(
            name: $0.name, value: $0.value, assetClass: $0.assetClass,
            ticker: $0.ticker, sheet: $0.sheet, section: nil
        )
    })
}

#Preview("Sankey — AX5") {
    SankeyPreviewHost()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
