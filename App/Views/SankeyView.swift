import SwiftUI

/// The Sankey flow: a trunk carrying one total, fanning right into the sheets
/// (or sections) it is made of.
///
/// All of the arithmetic is in `Shared/Sankey.swift`; this view scales the unit
/// box to whatever it is given, draws the ribbons, and decides where the labels
/// live. It renders nothing when the flow has fewer than two bands — see
/// `Sankey.Layout.isMeaningful` — so a caller should gate its section heading on
/// `Sankey.isWorthDrawing(_:)` rather than on this view's presence.
///
/// **Why it fits a phone.** The proportional encoding runs down the screen, not
/// across it: a phone has vertical room to spare inside a scroll view and almost
/// none horizontally. It is also why there are exactly two columns; a third
/// would take its width out of the one thing that needs it, the gap the ribbons
/// curve through.
///
/// Following Kubera's own cash-flow Sankey, the labels sit *over* the ribbons
/// rather than in a reserved column beside them, which is what buys the ribbons
/// the whole width — a 128pt label column costs 40% of a phone's card. The
/// reference draws them white-on-pastel and the bottom half of that image is
/// unreadable; these use `Theme.text` over a ribbon that never exceeds 30%
/// opacity, which holds ~9:1 in light mode and ~6.8:1 in dark.
struct SankeyView: View {
    let source: String
    let branches: [Sankey.Branch]
    let currency: String
    var masked: Bool = false
    var compact: Bool = true
    /// What VoiceOver calls the whole diagram. The caller knows what the bands
    /// were grouped by; this view only knows their names.
    var accessibilityTitle: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    @ScaledMetric(relativeTo: .footnote) private var labelledHeight: CGFloat = 300
    @ScaledMetric(relativeTo: .footnote) private var labelledBandMinimum: CGFloat = 36
    /// A cap, not a reserved column: the label is right-aligned against its node
    /// bar and only takes the width it needs. Long sheet names truncate rather
    /// than reaching back into the fan where the ribbons are still crossing.
    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 150
    @ScaledMetric(relativeTo: .footnote) private var labelGap: CGFloat = 8
    @ScaledMetric(relativeTo: .footnote) private var swatchSize: CGFloat = 10

    /// The diagram's size once the labels have moved out of it. Deliberately
    /// *not* `@ScaledMetric`: at accessibility sizes these would be multiplied
    /// by two and a half, and a 750pt-tall picture with no text in it is not
    /// what someone asking for larger text wants.
    private static let unlabelledHeight: CGFloat = 200
    private static let unlabelledBandMinimum: CGFloat = 16

    // MARK: - Body

    var body: some View {
        let flow = flow
        if flow.isMeaningful, let trunk = flow.source {
            let unit = Format.unit(spanning: flow.bands.map(\.value), compact: compact)

            VStack(alignment: .leading, spacing: 12) {
                // At accessibility sizes nothing can sit inside the diagram, so
                // the trunk gets a heading row and the bands get the legend.
                if usesLegend {
                    header(trunk)
                }
                diagram(flow, unit: unit)
                    .frame(height: diagramHeight)
                if usesLegend {
                    legend(flow, unit: unit)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityTitle ?? "\(source) flow")
        }
    }

    /// At accessibility sizes a band's name no longer fits beside its band — a
    /// single word is taller than the band it belongs to — so the labels move
    /// out into a stacked legend below and the diagram keeps only its shapes.
    /// The ribbons still carry the proportions, and the luminance ramp ties each
    /// legend row to its band, top to bottom, largest first.
    private var usesLegend: Bool { typeSize.isAccessibilitySize }

    /// The most of the box the clamped minimums are allowed to claim.
    ///
    /// Past this the diagram stops meaning anything: the floors have taken the
    /// height, and the bands above the floor are being proportional inside
    /// whatever is left, so a 15% band and a 5% band come out the same size. The
    /// fix is to grow the box rather than to shrink the bands — a taller card
    /// costs a scroll, a flattened diagram costs the truth.
    private static let maximumFloorShare: CGFloat = 0.55

    /// How many bands the fold will produce. Depends only on the values, not on
    /// the geometry, which is what lets the height be decided before the layout
    /// that needs it.
    private var bandCount: Int { Sankey.fold(branches).count }

    private var diagramHeight: CGFloat {
        let base = usesLegend ? Self.unlabelledHeight : labelledHeight
        guard bandCount > 0 else { return base }
        return max(base, CGFloat(bandCount) * bandMinimum / Self.maximumFloorShare)
    }

    /// The floor a band is clamped to, handed to the layout as a fraction of the
    /// height being drawn into. With labels beside the bands the floor is two
    /// lines of text; without them it only has to stay visible.
    private var bandMinimum: CGFloat {
        usesLegend ? Self.unlabelledBandMinimum : labelledBandMinimum
    }

    private var flow: Sankey.Layout {
        Sankey.layout(
            source: source,
            branches: branches,
            geometry: Sankey.Geometry(minimumThickness: Double(bandMinimum / diagramHeight))
        )
    }

    // MARK: - Header

    /// Names the trunk and states what it carries, which is the one figure the
    /// bands are shares of.
    private func header(_ trunk: Sankey.Node) -> some View {
        let name = Text(trunk.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        let total = Text(Format.money(trunk.value, currency: currency, masked: masked, compact: compact))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)

        // Name over total at accessibility sizes; the two would otherwise
        // collide mid-row, the same way the composition rows do.
        let stack = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        return stack {
            name
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            total
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Diagram

    private func diagram(_ flow: Sankey.Layout, unit: Format.Unit) -> some View {
        GeometryReader { proxy in
            let box = proxy.size

            ZStack(alignment: .topLeading) {
                shapes(flow, in: box)
                if !usesLegend {
                    trunkLabel(flow, in: box)
                    ForEach(flow.bands) { band in
                        // Right-aligned so every label ends on the same line,
                        // just clear of the node bars, the way the reference
                        // stacks its category names.
                        bandLabel(band, unit: unit)
                            .frame(width: labelWidth, alignment: .trailing)
                            .position(
                                x: band.box.x * box.width - labelGap - labelWidth / 2,
                                y: band.box.midY * box.height
                            )
                    }
                }
            }
        }
    }

    /// The trunk's name and total, laid over the widest ribbon leaving it —
    /// where the reference puts "Income $63,922". Centred on the largest trunk
    /// segment rather than on the trunk itself: the segments are contiguous, so
    /// the largest is the one stretch of the left edge with room for two lines.
    @ViewBuilder
    private func trunkLabel(_ flow: Sankey.Layout, in box: CGSize) -> some View {
        if let trunk = flow.source, let widest = Sankey.trunkSegments(flow).first {
            VStack(alignment: .leading, spacing: 1) {
                Text(trunk.name)
                    .font(.footnote.weight(.semibold))
                Text(Format.money(trunk.value, currency: currency, masked: masked, compact: compact))
                    .font(.headline)
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: labelWidth, alignment: .leading)
            .position(
                x: trunk.box.maxX * box.width + labelGap + labelWidth / 2,
                y: widest.midY * box.height
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// The drawing, hidden from VoiceOver as one piece: the labels beside it (or
    /// the legend below it) say everything it says, and two elements reading out
    /// the same band is one too many.
    private func shapes(_ flow: Sankey.Layout, in box: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(flow.links) { link in
                ribbon(link, in: box).fill(ribbonGradient(link.rank))
            }
            // One capsule for the whole trunk, as in the reference: the ribbons
            // already say where its money goes, and a segmented trunk restates
            // that in a bar 8 points wide.
            if let trunk = flow.source {
                capsule(trunk.box, in: box).fill(trunkColor)
            }
            ForEach(flow.bands) { band in
                capsule(band.box, in: box).fill(bandColor(band.rank ?? 0))
            }
        }
        .accessibilityHidden(true)
    }



    /// The standard Sankey ribbon: two cubics whose control points both sit at
    /// the horizontal midpoint of the gap, so the curve leaves the trunk and
    /// arrives at the band horizontally instead of shearing into either.
    private func ribbon(_ link: Sankey.Link, in size: CGSize) -> Path {
        let x0 = link.sourceX * size.width
        let x1 = link.targetX * size.width
        let cx = link.controlX * size.width
        let sourceTop = link.sourceTop * size.height
        let sourceBottom = link.sourceBottom * size.height
        let targetTop = link.targetTop * size.height
        let targetBottom = link.targetBottom * size.height

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
    private func capsule(_ box: Sankey.Box, in size: CGSize) -> Path {
        let frame = CGRect(
            x: box.x * size.width,
            y: box.y * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
        guard frame.width > 0, frame.height > 0 else { return Path(frame) }
        return Path(roundedRect: frame, cornerRadius: min(frame.width, frame.height) / 2)
    }

    // MARK: - Labels

    private func bandLabel(_ band: Sankey.Node, unit: Format.Unit) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(band.name)
                .font(.footnote.weight(.semibold))
            Text(amountText(band, unit: unit))
                .font(.caption2)
                .monospacedDigit()
        }
        // Both lines in `Theme.text` rather than the amount in `Theme.dim`: over
        // a ribbon `dim` falls to about 1.9:1, which is the mistake that makes
        // the bottom half of the reference image unreadable. The legend below
        // sits on the card and can afford `dim`; this cannot.
        .foregroundStyle(Theme.text)
        // One line each: two lines of a wrapped name would be taller than the
        // band the label belongs to, and the labels would start overlapping.
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.name)
        .accessibilityValue(accessibilityValue(band, unit: unit))
    }

    private func legend(_ flow: Sankey.Layout, unit: Format.Unit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(flow.bands) { band in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // A rounded square rather than a dot: at these sizes it has
                    // to read as the same object as the band it stands for.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bandColor(band.rank ?? 0))
                        .frame(width: swatchSize, height: swatchSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(band.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(amountText(band, unit: unit))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.dim)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(band.name)
                .accessibilityValue(accessibilityValue(band, unit: unit))
            }
        }
    }

    /// One unit across every band, the way the composition column does it:
    /// per-value compaction puts "$130K" two rows above "$74,000".
    private func amountText(_ band: Sankey.Node, unit: Format.Unit) -> String {
        let money = Format.money(band.value, currency: currency, masked: masked, unit: unit)
        return "\(money) · \(Format.percent(band.percent, signed: false))"
    }

    /// The exact share, spoken. The drawn band is clamped to a minimum height
    /// and so is only approximately proportional; this figure never is.
    private func accessibilityValue(_ band: Sankey.Node, unit: Format.Unit) -> String {
        let money = Format.money(band.value, currency: currency, masked: masked, unit: unit)
        return "\(money), \(Format.percent(band.percent, signed: false)) of \(source)"
    }

    // MARK: - Colour

    /// Monochrome by policy: green and red mean direction of change here, not
    /// category, so the bands separate by luminance in value order instead. The
    /// darkest band is the largest, which is also the reading order.
    private func bandColor(_ rank: Int) -> Color {
        let steps: [Double] = contrast == .increased
            ? [1, 0.88, 0.76, 0.65, 0.55, 0.46]
            : [0.92, 0.74, 0.58, 0.44, 0.32, 0.22]
        return Theme.text.opacity(steps[min(max(rank, 0), steps.count - 1)])
    }

    /// The trunk, and the tone every ribbon leaves it at.
    private var trunkColor: Color {
        Theme.text.opacity(contrast == .increased ? 1 : 0.92)
    }

    /// Ribbons run at a fraction of their band's weight for two reasons: they
    /// cover most of the diagram's area, and — unlike in the reference — the
    /// labels sit on top of them, so this ceiling is also the contrast budget.
    /// Raising it above 0.30 is what would make the labels unreadable.
    private func ribbonColor(_ rank: Int) -> Color {
        let steps: [Double] = contrast == .increased
            ? [0.42, 0.37, 0.32, 0.28, 0.24, 0.21]
            : [0.30, 0.25, 0.20, 0.16, 0.13, 0.10]
        return Theme.text.opacity(steps[min(max(rank, 0), steps.count - 1)])
    }

    /// Every ribbon leaves the trunk at one shared tone and arrives at its own,
    /// which is the reference's green-to-category wash rendered in the one
    /// palette this app has. The gradient resolves across the view's bounds, so
    /// all the ribbons share an axis and the fan reads as a single object.
    private func ribbonGradient(_ rank: Int) -> LinearGradient {
        LinearGradient(
            colors: [Theme.text.opacity(contrast == .increased ? 0.30 : 0.20), ribbonColor(rank)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#if DEBUG
private struct SankeyPreviewHost: View {
    var level: OverviewModules.CompositionLevel = .sheet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Flow")
                Card {
                    SankeyView(
                        source: "Assets",
                        branches: Sankey.branches(from: DemoData.detail.assets, by: level),
                        currency: DemoData.detail.currency ?? "USD",
                        accessibilityTitle: "Assets by \(level.rawValue)"
                    )
                }
            }
            // 20 to match the Overview screen's own inset, so the preview shows
            // the real width the labels have to fit into.
            .padding(.horizontal, 20)
        }
        .background(Theme.background)
    }
}

// Every figure below comes from `DemoData` — a synthetic ~$1.2M book. This
// repository is public.
#Preview("Sankey — by sheet") {
    SankeyPreviewHost()
}

#Preview("Sankey — dark") {
    SankeyPreviewHost()
        .preferredColorScheme(.dark)
}

/// Ten assets over six sections is the long tail at its worst, so this is the
/// preview that shows the fold and the minimum-thickness clamp doing work.
#Preview("Sankey — by section") {
    SankeyPreviewHost(level: .section)
}

#Preview("Sankey — AX5") {
    SankeyPreviewHost()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
