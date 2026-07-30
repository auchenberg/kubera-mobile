import Foundation

/// Layout maths for the Overview screen's Sankey: how one total splits into
/// bands, and where every ribbon edge sits.
///
/// Foundation-only and pure, exactly like `OverviewChart` and `OverviewModules`
/// — the test bundle compiles this without the app target, and `SankeyView`
/// holds no arithmetic of its own.
///
/// Everything comes out in a unit box: x rightward, y downward, both 0…1. The
/// view multiplies by its own size, so nothing here has an opinion about points.
///
/// **Two columns, by design.** A source trunk and one row of bands is all a
/// 393pt-wide phone has room for. A third column spends another node bar and
/// another ribbon gap out of the same width, and leaves the middle column's
/// labels nowhere to stand — `total → sheet → section` is a desktop diagram.
/// The `Branch` list is therefore flat: one parent, its children, and nothing
/// deeper.
enum Sankey {
    // MARK: - Input

    /// One child of the source: a sheet, a section, an asset class — whatever
    /// the caller grouped by. `value` is a magnitude, not a signed balance.
    struct Branch: Hashable, Sendable {
        let name: String
        let value: Double
    }

    /// The unit-space knobs. Defaults are tuned for a phone-width card; the
    /// view overrides `minimumThickness` with its own floor in points divided by
    /// the height it is drawing into, which is the only way a fraction here can
    /// promise a band big enough to put a label beside.
    struct Geometry: Hashable, Sendable {
        /// Width of the source trunk, as a fraction of the box.
        var sourceWidth: Double = 0.035
        /// Width of a band's end cap, as a fraction of the box.
        var bandWidth: Double = 0.035
        /// Vertical space between two bands. Present only on the band side: the
        /// trunk is contiguous, because the money leaving it is.
        var bandGap: Double = 0.014
        /// Shortest a band may be drawn, as a fraction of the box height.
        var minimumThickness: Double = 0.1

        init(
            sourceWidth: Double = 0.035,
            bandWidth: Double = 0.035,
            bandGap: Double = 0.014,
            minimumThickness: Double = 0.1
        ) {
            self.sourceWidth = sourceWidth
            self.bandWidth = bandWidth
            self.bandGap = bandGap
            self.minimumThickness = minimumThickness
        }
    }

    // MARK: - Output

    /// A rectangle in the unit box. Deliberately not `CGRect`: this file must
    /// stay free of CoreGraphics so the maths reads as maths.
    struct Box: Hashable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midY: Double { y + height / 2 }
    }

    /// The trunk or one band.
    struct Node: Hashable, Identifiable, Sendable {
        let id: String
        let name: String
        let value: Double
        /// Share of the flow's total, 0–100. Share of what the trunk carries,
        /// not of net worth — the bands do not sum to net worth.
        let percent: Double
        let box: Box
        /// Rank among the bands, largest first, so a view can index a colour
        /// ramp without re-sorting. The trunk is `nil`.
        let rank: Int?
    }

    /// One ribbon. Carries the four edge positions rather than a path, because
    /// the path is the view's business and the arithmetic is this file's.
    struct Link: Hashable, Identifiable, Sendable {
        let id: String
        let sourceID: String
        let targetID: String
        let value: Double
        /// Rank of the band this ribbon feeds, matching `Node.rank`.
        let rank: Int

        let sourceX: Double
        let targetX: Double
        let sourceTop: Double
        let sourceBottom: Double
        let targetTop: Double
        let targetBottom: Double

        /// Both cubic control points sit here — the horizontal midpoint of the
        /// gap. That is what makes a Sankey ribbon leave and arrive horizontally
        /// instead of shearing into its node.
        var controlX: Double { (sourceX + targetX) / 2 }
    }

    struct Layout: Hashable, Sendable {
        let source: Node?
        let bands: [Node]
        let links: [Link]
        /// What the trunk represents: the sum of the bands actually drawn, not
        /// whatever total the caller had in mind. A diagram whose trunk claims
        /// more than its ribbons carry is a lie about conservation, and
        /// conservation is the only thing a Sankey says that a bar list doesn't.
        let total: Double

        static let empty = Layout(source: nil, bands: [], links: [], total: 0)

        var isEmpty: Bool { bands.isEmpty }

        /// Whether a flow diagram earns its space. One band is a rectangle with
        /// a rectangle next to it: it states "all of it is here", which a
        /// sentence states better. Callers should show their list instead.
        var isMeaningful: Bool { bands.count >= 2 }
    }

    // MARK: - Defaults

    /// Where the folded tail lands. Matches `OverviewModules.otherGroupName`, so
    /// the same sheet reads by the same name in both modules.
    static let otherBandName = OverviewModules.otherGroupName

    /// Stricter than the composition list's 6 rows and 3%, on purpose. A short
    /// bar in a list is still a labelled row you can read; a 3% ribbon is two
    /// points of a curve, and it drags a minimum-thickness clamp onto every band
    /// beside it. Fewer, fatter ribbons is the whole reason this fits a phone.
    ///
    /// Four plus "Other" is where the demo book's sections stop degenerating:
    /// at six bands the clamped minimums take so much of the box that a 15%
    /// section and a 5% one come out the same height, which is a diagram that
    /// states something false. See `thicknesses(_:available:minimum:)`.
    static let defaultMaximumBands = 4
    static let defaultMinimumPercent: Double = 5

    // MARK: - Building branches

    /// Branches from the asset book, grouped the way the Composition module
    /// groups it.
    ///
    /// `OverviewModules` does the labelling — including parking an asset with no
    /// sheet under "Unsorted" rather than dropping real money — and `Sankey`
    /// does the folding. The composition module's own cap and threshold are
    /// switched off here on purpose: folding twice against two different rules
    /// would produce an "Other" that means something different in each module
    /// while carrying the same name.
    static func branches(
        from assets: [PortfolioDetail.Asset],
        by level: OverviewModules.CompositionLevel
    ) -> [Branch] {
        OverviewModules
            .composition(assets, by: level, maximumGroups: .max, minimumPercent: 0)
            .map { Branch(name: $0.name, value: $0.value) }
    }

    /// Whether these branches are worth a diagram, without building one. Lets a
    /// screen decide whether to print the section heading at all, rather than
    /// heading an empty space.
    static func isWorthDrawing(
        _ branches: [Branch],
        maximumBands: Int = defaultMaximumBands,
        minimumPercent: Double = defaultMinimumPercent
    ) -> Bool {
        fold(branches, maximumBands: maximumBands, minimumPercent: minimumPercent).count >= 2
    }

    // MARK: - Folding

    /// The tail folded into one "Other" band: everything past `maximumBands`,
    /// and everything under `minimumPercent` of the total.
    ///
    /// Largest first, with the name as the tiebreak, so two runs over the same
    /// input produce the same order and therefore the same geometry.
    /// Non-positive branches are dropped rather than drawn — a ribbon's width is
    /// a magnitude, so a debt carried as a negative has no thickness, and
    /// mixing signs into one trunk breaks the conservation the diagram asserts.
    /// Callers wanting debts in the picture must pass them as their own positive
    /// flow.
    static func fold(
        _ branches: [Branch],
        maximumBands: Int = defaultMaximumBands,
        minimumPercent: Double = defaultMinimumPercent,
        otherName: String = otherBandName
    ) -> [Branch] {
        var ranked = branches.filter { $0.value > 0 && $0.value.isFinite }
        ranked.sort { left, right in
            left.value == right.value ? left.name < right.name : left.value > right.value
        }

        let total = ranked.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var kept: [Branch] = []
        var remainder: Double = 0
        for (index, branch) in ranked.enumerated() {
            let percent = branch.value / total * 100
            if index < maximumBands, percent >= minimumPercent {
                kept.append(branch)
            } else {
                remainder += branch.value
            }
        }

        guard remainder > 0 else { return kept }
        // An existing "Other" sheet absorbs the remainder rather than gaining a
        // duplicate band, the way `OverviewModules.composition` does. It keeps
        // its ranked position when it does, which is why "Other" can end up
        // above a smaller named band — it is a real group there, not a leftover.
        if let index = kept.firstIndex(where: { $0.name == otherName }) {
            kept[index] = Branch(name: otherName, value: kept[index].value + remainder)
        } else {
            kept.append(Branch(name: otherName, value: remainder))
        }
        return kept
    }

    // MARK: - Thickness

    /// Band heights filling exactly `available`, proportional to `values` except
    /// that none falls below `minimum`.
    ///
    /// **This makes the diagram not strictly proportional, and that is the
    /// trade.** A 4% sheet on a 300pt diagram is 12 points tall, which is a
    /// ribbon nobody can read a label beside and nobody can hit with a thumb.
    /// The clamp buys it back out of the bands that have height to spare, so
    /// the small band is legible and the large ones are a few percent short of
    /// truthful. The alternative — a hairline — is not more honest, it is just
    /// unreadable, and the percentage printed beside each band carries the exact
    /// figure regardless.
    ///
    /// The clamp set is grown smallest-first: once the smallest unclamped band's
    /// proportional share clears `minimum`, every larger one does too, so the
    /// rest can be settled in one pass. The result sums to `available` by
    /// construction.
    ///
    /// When `minimum * count` would not fit in `available` at all, the floor is
    /// unsatisfiable and every band splits the room equally — degrading to "all
    /// the same size" rather than to "some of them invisible".
    static func thicknesses(_ values: [Double], available: Double, minimum: Double) -> [Double] {
        let count = values.count
        guard count > 0 else { return [] }
        guard available > 0 else { return Array(repeating: 0, count: count) }

        let equal = Array(repeating: available / Double(count), count: count)
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return equal }

        let floor = max(minimum, 0)
        guard floor > 0 else { return values.map { available * max($0, 0) / total } }
        guard floor * Double(count) < available else { return equal }

        // Ascending by value, index breaking ties, so the walk is deterministic
        // for a set of equal values.
        let order = values.indices.sorted { left, right in
            values[left] == values[right] ? left < right : values[left] < values[right]
        }

        var result = Array(repeating: 0.0, count: count)
        var room = available
        var remaining = total

        for (rank, index) in order.enumerated() {
            let value = max(values[index], 0)
            let share = remaining > 0
                ? room * value / remaining
                : room / Double(count - rank)

            if share < floor {
                result[index] = floor
                room -= floor
                remaining -= value
            } else {
                for other in order[rank...] {
                    let otherValue = max(values[other], 0)
                    result[other] = remaining > 0
                        ? room * otherValue / remaining
                        : room / Double(count - rank)
                }
                break
            }
        }
        return result
    }

    // MARK: - Layout

    /// The whole diagram: a trunk labelled `source`, and one band per branch.
    ///
    /// Ribbons narrow slightly on their way right, because the trunk is
    /// contiguous while the bands are separated by `bandGap`. That is the normal
    /// look of a Sankey with node padding, and it is why the trunk's segments
    /// are cut from the *drawn* thicknesses rather than the raw values: cutting
    /// them from the raw values would make a clamped band's ribbon flare, which
    /// reads as the flow gaining money in transit.
    static func layout(
        source: String,
        branches: [Branch],
        geometry: Geometry = Geometry(),
        maximumBands: Int = defaultMaximumBands,
        minimumPercent: Double = defaultMinimumPercent,
        otherName: String = otherBandName
    ) -> Layout {
        let bands = fold(
            branches,
            maximumBands: maximumBands,
            minimumPercent: minimumPercent,
            otherName: otherName
        )
        guard !bands.isEmpty else { return .empty }

        let total = bands.reduce(0) { $0 + $1.value }
        guard total > 0 else { return .empty }

        // Gaps never eat more than half the box, however many bands there are or
        // whatever gap the caller asked for.
        let count = bands.count
        let gap = count > 1
            ? min(max(geometry.bandGap, 0), 0.5 / Double(count - 1))
            : 0
        let available = 1 - gap * Double(count - 1)

        let heights = thicknesses(
            bands.map(\.value),
            available: available,
            minimum: geometry.minimumThickness
        )

        let sourceWidth = min(max(geometry.sourceWidth, 0), 0.2)
        let bandWidth = min(max(geometry.bandWidth, 0), 0.2)
        let sourceX = sourceWidth
        let bandX = 1 - bandWidth

        let sourceNode = Node(
            id: "source",
            name: source,
            value: total,
            percent: 100,
            box: Box(x: 0, y: 0, width: sourceWidth, height: 1),
            rank: nil
        )

        var nodes: [Node] = []
        var links: [Link] = []
        var bandY: Double = 0
        var trunkY: Double = 0

        for (rank, band) in bands.enumerated() {
            let height = heights[rank]
            // The trunk spans the full height with no gaps, so its segments are
            // the band heights stretched by whatever the gaps took.
            let trunkHeight = available > 0 ? height / available : 0

            let id = "band.\(rank).\(band.name)"
            nodes.append(Node(
                id: id,
                name: band.name,
                value: band.value,
                percent: band.value / total * 100,
                box: Box(x: bandX, y: bandY, width: bandWidth, height: height),
                rank: rank
            ))
            links.append(Link(
                id: "link.\(id)",
                sourceID: sourceNode.id,
                targetID: id,
                value: band.value,
                rank: rank,
                sourceX: sourceX,
                targetX: bandX,
                sourceTop: trunkY,
                sourceBottom: trunkY + trunkHeight,
                targetTop: bandY,
                targetBottom: bandY + height
            ))

            bandY += height + gap
            trunkY += trunkHeight
        }

        return Layout(source: sourceNode, bands: nodes, links: links, total: total)
    }

    /// The trunk's own segments, in band order — the slices a view fills so the
    /// trunk is coloured by where its money goes rather than being one grey bar.
    /// Derived from the links so the two can never disagree.
    static func trunkSegments(_ layout: Layout) -> [Box] {
        guard let source = layout.source else { return [] }
        return layout.links.map { link in
            Box(
                x: source.box.x,
                y: link.sourceTop,
                width: source.box.width,
                height: link.sourceBottom - link.sourceTop
            )
        }
    }
}
