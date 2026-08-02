import Foundation

/// Layout maths for the Overview screen's Sankey: how the asset book flows from
/// its sections through its sheets into one Assets trunk, and back out into net
/// worth and debts — plus where every ribbon edge sits.
///
/// Foundation-only and pure, exactly like `OverviewChart` and `OverviewModules`
/// — the test bundle compiles this without the app target, and `SankeyView`
/// holds no arithmetic of its own.
///
/// Everything comes out in a unit box: x rightward, y downward, both 0…1. The
/// view multiplies by its own size, so nothing here has an opinion about points.
///
/// **N columns, since the canvas stopped being the card.** This used to be two
/// columns "by design", because a 393pt-wide phone had room for a trunk and one
/// row of bands and nothing else. That constraint is gone: `SankeyView` now
/// draws onto a fixed wide canvas inside a horizontal `ScrollView`, so the
/// diagram is as wide as it needs to be and the phone slides along it. What the
/// width buys is the level Kubera's own web diagram shows and the old one could
/// not — `section → sheet → Assets → net worth + debts`, where a sheet is both
/// a destination and a source, which is the one thing a flow diagram says that a
/// pair of bar lists doesn't.
///
/// The geometry engine is `layout(_:geometry:)`: it takes a `Flow` — columns of
/// items plus the ribbons between adjacent columns — and places everything.
/// `assetFlow(from:debtTotal:)` builds that `Flow` from the asset book, and the
/// old two-column `layout(source:branches:)` is a thin wrapper over the same
/// engine so there is only ever one set of arithmetic to be wrong.
enum Sankey {
    // MARK: - Input

    /// One child of a parent group: a sheet, a section, an asset class —
    /// whatever the caller grouped by. `value` is a magnitude, not a signed
    /// balance.
    struct Branch: Hashable, Sendable {
        let name: String
        let value: Double
    }

    /// One node of a flow before it has been laid out.
    ///
    /// `id` must be unique across the whole `Flow`, not just its column: the
    /// engine resolves ribbons by id. `assetFlow` keys leaves by *(sheet,
    /// section)* rather than by section name for exactly this reason — two
    /// sheets are each allowed an "Equity" section, and they are two different
    /// piles of money.
    struct Item: Hashable, Sendable {
        let id: String
        let name: String
        let value: Double

        init(id: String, name: String, value: Double) {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    /// One column, in top-to-bottom draw order. The caller owns that order:
    /// vertical position is the only tool a Sankey has for keeping ribbons from
    /// crossing, and only the caller knows which nodes belong beside which.
    struct Stage: Hashable, Sendable {
        let items: [Item]

        init(_ items: [Item]) { self.items = items }
    }

    /// One ribbon before it has been laid out. Only edges between adjacent
    /// columns are drawn; anything else is dropped rather than drawn skipping a
    /// column, which would read as money that missed a stage.
    struct Edge: Hashable, Sendable {
        let sourceID: String
        let targetID: String
        let value: Double

        init(from sourceID: String, to targetID: String, value: Double) {
            self.sourceID = sourceID
            self.targetID = targetID
            self.value = value
        }
    }

    /// A whole flow, unplaced: the columns and the ribbons between them.
    ///
    /// Separate from the placed `Diagram` on purpose. Grouping and folding are
    /// decided by the data and cost real work; placement depends on the height
    /// the view happens to have, which it only learns during layout. The screen
    /// builds a `Flow` once and the view places it however tall it ends up.
    struct Flow: Hashable, Sendable {
        let stages: [Stage]
        let edges: [Edge]

        init(stages: [Stage], edges: [Edge]) {
            self.stages = stages
            self.edges = edges
        }

        static let empty = Flow(stages: [], edges: [])

        var isEmpty: Bool { stages.isEmpty }

        /// Whether a flow diagram earns its space.
        ///
        /// Every column but the last is a *breakdown*; the last one is where the
        /// money ends up. "All of it is in one sheet, and here is your mortgage"
        /// is two sentences, not a flow, so a split in the final column alone
        /// does not qualify — some breakdown column has to have at least two
        /// nodes in it. Callers gate their section heading on this rather than
        /// on the view's presence, so a heading is never printed over nothing.
        var isMeaningful: Bool {
            stages.count >= 2 && stages.dropLast().contains { $0.items.count >= 2 }
        }

        /// The node the whole flow passes through, before placement — see
        /// `Diagram.trunk`. A screen that wants to name the total without
        /// laying anything out reads it here.
        var trunk: Item? { stages.last { $0.items.count == 1 }?.items.first }
    }

    /// The unit-space knobs. Defaults are tuned for the wide canvas; the view
    /// overrides `minimumThickness` with its own floor in points divided by the
    /// height it is drawing into, which is the only way a fraction here can
    /// promise a band big enough to put a label beside.
    struct Geometry: Hashable, Sendable {
        /// Width of the leftmost column's node bars, as a fraction of the box.
        /// Only the two-column `layout(source:branches:)` uses this — in a
        /// multi-stage flow every column is both a source and a target, so they
        /// all take `bandWidth` and a wider first bar would just look like a
        /// mistake.
        var sourceWidth: Double = 0.035
        /// Width of a node bar, as a fraction of the box.
        var bandWidth: Double = 0.035
        /// Vertical space between two nodes in the same column. Applied to every
        /// column, including the one the money leaves: with more than two
        /// columns there is no single "trunk" that must stay contiguous, and a
        /// column drawn without gaps reads as one bar rather than as several
        /// nodes. A column holding a single node has no gaps and so still fills
        /// the box exactly.
        var bandGap: Double = 0.014
        /// Shortest a node may be drawn, as a fraction of the box height. Capped
        /// per column by `maximumFloorShare` — see `layout(_:geometry:)`.
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

    /// One node bar.
    struct Node: Hashable, Identifiable, Sendable {
        let id: String
        let name: String
        let value: Double
        /// Share of its own column's total, 0–100. Under conservation — which
        /// every column of a flow this file builds satisfies — that is also its
        /// share of the whole, which is why a net worth node can print "77%"
        /// and mean it.
        let percent: Double
        let box: Box
        /// Rank *within its column*, largest first, so a view can index a colour
        /// ramp without re-sorting. Note that this is not the drawing order: the
        /// leaves are drawn grouped under their sheet, so a small leaf of a big
        /// sheet sits above a big leaf of a small one while still taking the
        /// paler tone. The two-column layout's trunk is `nil`.
        let rank: Int?
        /// Which column, counting from the left.
        let stage: Int
    }

    /// One ribbon. Carries the four edge positions rather than a path, because
    /// the path is the view's business and the arithmetic is this file's.
    struct Link: Hashable, Identifiable, Sendable {
        let id: String
        let sourceID: String
        let targetID: String
        let value: Double
        /// Rank of the node this ribbon feeds, matching `Node.rank`.
        let rank: Int
        /// Rank of the node it leaves. The wash between the two tones is what
        /// ties a ribbon to both of its ends.
        let sourceRank: Int
        /// The column this ribbon leaves, so a view can treat the gaps
        /// differently without looking either node up.
        let stage: Int

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

    /// A placed flow: every column's nodes, every ribbon, ready to draw.
    struct Diagram: Hashable, Sendable {
        /// Columns left to right; each in top-to-bottom draw order.
        let columns: [[Node]]
        let links: [Link]
        /// What the first column carries — the sum of the nodes actually drawn,
        /// not whatever total the caller had in mind. A diagram whose trunk
        /// claims more than its ribbons carry is a lie about conservation, and
        /// conservation is the only thing a Sankey says that a bar list doesn't.
        let total: Double

        static let empty = Diagram(columns: [], links: [], total: 0)

        var isEmpty: Bool { columns.isEmpty }

        /// See `Flow.isMeaningful` — the same rule, applied after placement.
        var isMeaningful: Bool {
            columns.count >= 2 && columns.dropLast().contains { $0.count >= 2 }
        }

        /// Every node, left to right then top to bottom. For views that want one
        /// `ForEach` over the whole drawing.
        var nodes: [Node] { columns.flatMap { $0 } }

        /// The node the whole flow passes through — the rightmost column that
        /// holds it in a single bar. The Overview's Assets node, which is what a
        /// header names and what the percentages are shares of.
        var trunk: Node? { columns.last { $0.count == 1 }?.first }

        /// The coarsest breakdown still in the diagram: the column feeding the
        /// trunk directly.
        ///
        /// This is the level that becomes the legend at accessibility sizes.
        /// Sheets rather than sections, because a legend is read as a list and
        /// five sheets can be held in the head where twelve sections cannot —
        /// and because every other column rolls up into this one, so it is the
        /// one that can stand alone.
        var summaryColumn: [Node] {
            guard let index = columns.lastIndex(where: { $0.count == 1 }), index > 0 else {
                return columns.first ?? []
            }
            return columns[index - 1]
        }
    }

    /// The two-column result: a trunk labelled `source` and one row of bands.
    /// Kept because it is a fair description of any single split, and because
    /// the folding and thickness rules are easiest to state against it.
    struct Layout: Hashable, Sendable {
        let source: Node?
        let bands: [Node]
        let links: [Link]
        let total: Double

        static let empty = Layout(source: nil, bands: [], links: [], total: 0)

        var isEmpty: Bool { bands.isEmpty }

        /// Whether a flow diagram earns its space. One band is a rectangle with
        /// a rectangle next to it: it states "all of it is here", which a
        /// sentence states better. Callers should show their list instead.
        var isMeaningful: Bool { bands.count >= 2 }
    }

    // MARK: - Defaults

    /// Where a folded tail lands. Matches `OverviewModules.otherGroupName`, so
    /// the same sheet reads by the same name in both modules.
    static let otherBandName = OverviewModules.otherGroupName

    /// Stricter than the composition list's 6 rows and 3%, on purpose. A short
    /// bar in a list is still a labelled row you can read; a 3% ribbon is two
    /// points of a curve, and it drags a minimum-thickness clamp onto every band
    /// beside it.
    ///
    /// Four plus "Other" is where the demo book's sheets stop degenerating: at
    /// six bands the clamped minimums take so much of the box that a 15% sheet
    /// and a 5% one come out the same height, which is a diagram that states
    /// something false. See `thicknesses(_:available:minimum:)`.
    static let defaultMaximumBands = 4
    static let defaultMinimumPercent: Double = 5

    /// How many leaves the whole first column may hold, across every sheet.
    ///
    /// The canvas is free to grow sideways but not downwards — it lives in a
    /// card on a vertically scrolling screen, so its height stays in the
    /// 300–340pt range. Twelve leaves over 300 points is a 25pt pitch, which is
    /// one line of `.caption` text with a hair of air around it. Thirteen is a
    /// column of labels that touch. The budget is split between the sheets in
    /// `assetFlow(from:debtTotal:)`, largest sheet first.
    static let defaultMaximumLeaves = 12

    /// The most of a column the clamped minimums may claim.
    ///
    /// Past this the column stops meaning anything: the floors have taken the
    /// height, and the nodes above the floor are being proportional inside
    /// whatever is left, so a 15% node and a 5% node come out the same size. So
    /// rather than honouring the caller's floor and flattening the column, the
    /// engine lowers the floor to fit — a column of twelve leaves gets a
    /// shorter minimum than a column of two, which is the only way one floor
    /// expressed in points can serve columns of different lengths.
    static let maximumFloorShare: Double = 0.55

    /// The names the Overview's flow uses. "Net worth" rather than the web
    /// app's "Net Worth": the rest of this screen sentence-cases its labels.
    static let assetsNodeName = "Assets"
    static let netWorthNodeName = "Net worth"
    static let debtsNodeName = "Debts"

    // MARK: - Building branches

    /// Branches from the asset book, grouped the way the Composition module
    /// groups it. The two-column entry point's input; the multi-stage flow is
    /// built by `assetFlow(from:debtTotal:)`, which needs both levels at once.
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

    /// Whether these branches are worth a diagram, without building one. The
    /// multi-stage equivalent is `Flow.isMeaningful`, which the screen reads off
    /// the flow it has already built.
    static func isWorthDrawing(
        _ branches: [Branch],
        maximumBands: Int = defaultMaximumBands,
        minimumPercent: Double = defaultMinimumPercent
    ) -> Bool {
        fold(branches, maximumBands: maximumBands, minimumPercent: minimumPercent).count >= 2
    }

    // MARK: - The Overview's asset flow

    /// The Overview's diagram: `section → sheet → Assets → net worth + debts`.
    ///
    /// Grouping only — no geometry, so a screen can build this once and let the
    /// view place it against whatever height it has.
    ///
    /// **Leaves are keyed by (sheet, section), never by section name.** Two
    /// sheets may each have an "Equity" section and they are two different piles
    /// of money; merging them would draw one leaf feeding two sheets, which is a
    /// shape this diagram has no way to read.
    ///
    /// **Where the tails go.** The sheet column folds under the usual
    /// `defaultMaximumBands` / `defaultMinimumPercent` rules. Each kept sheet
    /// then folds its own sections into a share of `maximumLeaves`, split
    /// between the sheets largest-first, so the leaf column stays inside the
    /// height the card has. A sheet's tail is named "Other" like everything
    /// else's — read beside its sheet, "Investments / Other" is unambiguous.
    ///
    /// The folded *sheet* tail is the odd one: its children are the sheets it
    /// absorbed, not their sections. A group of small sheets broken down into
    /// sections one level further would be four names nobody can place, whereas
    /// naming the absorbed sheets is precisely what says what "Other" is.
    ///
    /// **Columns that only restate the next one are dropped.** A book where no
    /// asset carries a section produces a leaf column of nothing but "Unsorted",
    /// and a book with one sheet produces a sheet column identical to Assets.
    /// Either way the column costs width and says nothing, so it goes.
    ///
    /// **Debts.** With `debtTotal <= 0` there is no outflow column at all: net
    /// worth would equal assets, and a column that repeats the one before it is
    /// a column that says nothing. Same when assets minus debts is not positive
    /// — a negative net worth cannot be drawn as one of two outflows, since a
    /// ribbon's width is a magnitude and the two would have to sum to something
    /// smaller than one of them. Those books end at Assets, which is still true.
    static func assetFlow(
        from assets: [PortfolioDetail.Asset],
        debtTotal: Double,
        assetsName: String = assetsNodeName,
        netWorthName: String = netWorthNodeName,
        debtsName: String = debtsNodeName,
        maximumSheets: Int = defaultMaximumBands,
        maximumLeaves: Int = defaultMaximumLeaves,
        minimumPercent: Double = defaultMinimumPercent,
        unsortedName: String = OverviewModules.unsortedGroupName,
        otherName: String = otherBandName
    ) -> Flow {
        // Sheet totals and (sheet, section) totals in one pass. Insertion order
        // is not preserved anywhere below — `fold` sorts by value with the name
        // as the tiebreak, so the same book always produces the same diagram.
        var sheetTotals: [String: Double] = [:]
        var sectionTotals: [String: [String: Double]] = [:]
        for asset in assets where asset.value > 0 && asset.value.isFinite {
            // An aggregate row summarises holdings the payload did not list, so
            // it belongs in the tail band rather than in "Unsorted", which means
            // money nobody filed. `fold` merges it with whatever else lands
            // there, and the columns still balance because its value is kept.
            let aggregate = PortfolioBook.isAggregateRow(asset.name)
            let sheet = aggregate ? otherName : label(asset.sheet, fallback: unsortedName)
            let section = aggregate ? otherName : label(asset.section, fallback: unsortedName)
            sheetTotals[sheet, default: 0] += asset.value
            sectionTotals[sheet, default: [:]][section, default: 0] += asset.value
        }

        let sheets = fold(
            sheetTotals.map { Branch(name: $0.key, value: $0.value) },
            maximumBands: maximumSheets,
            minimumPercent: minimumPercent,
            otherName: otherName
        )
        guard !sheets.isEmpty else { return .empty }

        let assetsTotal = sheets.reduce(0) { $0 + $1.value }
        guard assetsTotal > 0 else { return .empty }

        // Which sheets the fold swallowed, so the "Other" band can name them.
        let kept = Set(sheets.map(\.name))
        // Sorted rather than taken in the dictionary's order: these become
        // leaves, and a diagram that reshuffles between two runs over the same
        // book is a diagram that flickers.
        let absorbed = sheetTotals.keys
            .filter { !kept.contains($0) }
            .sorted { left, right in
                let leftValue = sheetTotals[left] ?? 0
                let rightValue = sheetTotals[right] ?? 0
                return leftValue == rightValue ? left < right : leftValue > rightValue
            }

        // Leaves per sheet, each inside its slice of the leaf budget.
        let budgets = split(maximumLeaves, between: sheets.count)
        var leavesBySheet: [(sheet: Branch, leaves: [Branch])] = []
        for (index, sheet) in sheets.enumerated() {
            var children = (sectionTotals[sheet.name] ?? [:])
                .map { Branch(name: $0.key, value: $0.value) }
            if sheet.name == otherName {
                // The tail band names the sheets it swallowed. A sheet the user
                // really did call "Other" contributes its own sections as well,
                // and a collision between the two just sums — they are the same
                // money either way.
                children.append(contentsOf: absorbed.map { Branch(name: $0, value: sheetTotals[$0] ?? 0) })
                children = merge(children)
            }
            leavesBySheet.append((
                sheet: sheet,
                leaves: fold(
                    children,
                    into: budgets[index],
                    minimumPercent: minimumPercent,
                    otherName: otherName
                )
            ))
        }

        // A leaf column of nothing but "Unsorted" is the sheet column with worse
        // names on it. Judged on the *sections* only: the tail sheet's leaves
        // name the sheets it swallowed, and those alone are not worth a column
        // that puts "Unsorted" beside every other sheet to get them.
        let leavesSaySomething = sectionTotals.values.contains { sections in
            sections.keys.contains { $0 != unsortedName }
        }
        // A single sheet is the Assets node with a different word on it.
        let sheetsSaySomething = sheets.count > 1

        var stages: [Stage] = []
        var edges: [Edge] = []

        let assetsID = "assets"
        let sheetID = { (name: String) in "sheet\(Self.idSeparator)\(name)" }
        let leafID = { (sheet: String, leaf: String) in
            "leaf\(Self.idSeparator)\(sheet)\(Self.idSeparator)\(leaf)"
        }

        if leavesSaySomething {
            // Sheets largest-first, and within each sheet its sections
            // largest-first. Grouping the leaves under their sheet's vertical
            // span is what keeps the fan from crossing itself; ordering both
            // levels by value is what keeps it monotonic inside the group.
            var items: [Item] = []
            for entry in leavesBySheet {
                for leaf in entry.leaves {
                    items.append(Item(
                        id: leafID(entry.sheet.name, leaf.name),
                        name: leaf.name,
                        value: leaf.value
                    ))
                }
            }
            stages.append(Stage(items))

            let parent = { (sheet: String) in sheetsSaySomething ? sheetID(sheet) : assetsID }
            for entry in leavesBySheet {
                for leaf in entry.leaves {
                    edges.append(Edge(
                        from: leafID(entry.sheet.name, leaf.name),
                        to: parent(entry.sheet.name),
                        value: leaf.value
                    ))
                }
            }
        }

        if sheetsSaySomething {
            stages.append(Stage(sheets.map {
                Item(id: sheetID($0.name), name: $0.name, value: $0.value)
            }))
            for sheet in sheets {
                edges.append(Edge(from: sheetID(sheet.name), to: assetsID, value: sheet.value))
            }
        }

        stages.append(Stage([Item(id: assetsID, name: assetsName, value: assetsTotal)]))

        let debts = debtTotal.isFinite ? debtTotal : 0
        let netWorth = assetsTotal - debts
        if debts > 0, netWorth > 0 {
            // Largest first, which for any book that is not underwater puts net
            // worth on top and the debt outflow at the bottom right — the shape
            // Kubera's own diagram has.
            let net = Item(id: "networth", name: netWorthName, value: netWorth)
            let owed = Item(id: "debts", name: debtsName, value: debts)
            let outflows: [Item] = netWorth >= debts ? [net, owed] : [owed, net]
            stages.append(Stage(outflows))
            for outflow in outflows {
                edges.append(Edge(from: assetsID, to: outflow.id, value: outflow.value))
            }
        }

        return Flow(stages: stages, edges: edges)
    }

    /// Separates the parts of a composed id. A control character, so no sheet or
    /// section name a user can type can forge one id into another.
    private static let idSeparator = "\u{001F}"

    private static func label(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? fallback : trimmed!
    }

    /// Same-named branches summed into one. Only the folded sheet tail can
    /// produce duplicates, and two bands with one name are two ribbons the
    /// reader has no way to tell apart.
    private static func merge(_ branches: [Branch]) -> [Branch] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for branch in branches {
            if totals[branch.name] == nil { order.append(branch.name) }
            totals[branch.name, default: 0] += branch.value
        }
        return order.map { Branch(name: $0, value: totals[$0] ?? 0) }
    }

    /// `budget` leaves shared between `count` sheets, remainder to the largest
    /// sheets first. Every sheet gets at least one leaf even when the budget
    /// cannot stretch that far — a sheet drawn with no leaf at all would be a
    /// ribbon arriving from nowhere.
    private static func split(_ budget: Int, between count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = max(budget / count, 1)
        let extra = max(budget - base * count, 0)
        return (0 ..< count).map { $0 < extra ? base + 1 : base }
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
    /// flow, the way `assetFlow(from:debtTotal:)` does.
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

    /// `fold`, but to a hard ceiling with "Other" counted inside it.
    ///
    /// `fold(_:maximumBands:)` keeps `maximumBands` named bands and may add an
    /// "Other" on top of them, which is the right shape when the cap is a
    /// statement about how many *names* fit. The leaf column's cap is instead a
    /// statement about how many *rows* fit in a fixed height, so here the tail
    /// has to come out of the allowance: if the first fold overshoots, one fewer
    /// name is kept and the tail takes the freed slot.
    static func fold(
        _ branches: [Branch],
        into limit: Int,
        minimumPercent: Double = defaultMinimumPercent,
        otherName: String = otherBandName
    ) -> [Branch] {
        guard limit > 0 else { return [] }
        let folded = fold(
            branches,
            maximumBands: limit,
            minimumPercent: minimumPercent,
            otherName: otherName
        )
        guard folded.count > limit else { return folded }
        return fold(
            branches,
            maximumBands: limit - 1,
            minimumPercent: minimumPercent,
            otherName: otherName
        )
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
    /// the same size" rather than to "some of them invisible". `layout` keeps a
    /// column out of that state by lowering the floor first; see
    /// `maximumFloorShare`.
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

    /// The geometry engine: every node placed, every ribbon's four edges found.
    ///
    /// Each column fills the box top to bottom, which is what makes conservation
    /// visible — the leaves, the sheets, Assets and the outflows are all the
    /// same total drawn four different ways, so they are all the same height.
    ///
    /// **Ribbon widths come from the drawn heights, not the raw values.** A
    /// ribbon's thickness where it lands is its share of the target node's face,
    /// weighted by how tall its *source* was drawn; its thickness where it
    /// leaves is its share of the source's face, weighted by how thick it
    /// arrives. Both faces are covered exactly and no ribbon can escape its
    /// node. Doing this from raw values instead would make a clamped node's
    /// ribbon flare, which reads as the flow gaining money in transit.
    ///
    /// Columns hold different numbers of nodes and therefore lose different
    /// amounts of height to gaps, so a ribbon from a crowded column into a
    /// sparse one widens slightly on the way. That is node padding doing its
    /// job, and it is the normal look of every Sankey drawn with it.
    ///
    /// Ribbons stack down a face in the *other* end's draw order: a sheet's
    /// incoming ribbons in leaf order, the Assets node's in sheet order. With
    /// the caller ordering leaves under their sheet, that is what stops the fan
    /// from crossing itself.
    static func layout(_ flow: Flow, geometry: Geometry = Geometry()) -> Diagram {
        layout(flow, geometry: geometry, widths: nil)
    }

    private static func layout(_ flow: Flow, geometry: Geometry, widths: [Double]?) -> Diagram {
        // A node with no thickness is dropped before it can take a floor's worth
        // of height off the ones that do.
        let columns = flow.stages.map { stage in
            stage.items.filter { $0.value > 0 && $0.value.isFinite }
        }
        guard !columns.isEmpty, columns.allSatisfy({ !$0.isEmpty }) else { return .empty }

        let count = columns.count
        let widthOf = { (column: Int) -> Double in
            min(max(widths?[column] ?? geometry.bandWidth, 0), 0.2)
        }
        let lastWidth = widthOf(count - 1)
        // Evenly spaced, with the last column's bar ending on the box's right
        // edge. Nothing here reserves room for labels: the label gutters live in
        // the view's canvas, outside the unit box, because only the view knows
        // how wide a line of text is.
        let xs: [Double] = count > 1
            ? (0 ..< count).map { Double($0) * (1 - lastWidth) / Double(count - 1) }
            : [0]

        var placed: [[Node]] = []
        var nodesByID: [String: Node] = [:]
        var drawIndexByID: [String: Int] = [:]
        var heightByID: [String: Double] = [:]

        for (column, items) in columns.enumerated() {
            let n = items.count
            // Gaps never eat more than half a column, however many nodes it has
            // or whatever gap the caller asked for.
            let gap = n > 1 ? min(max(geometry.bandGap, 0), 0.5 / Double(n - 1)) : 0
            let available = 1 - gap * Double(n - 1)
            let floor = min(
                max(geometry.minimumThickness, 0),
                maximumFloorShare * available / Double(n)
            )
            let heights = thicknesses(items.map(\.value), available: available, minimum: floor)
            let columnTotal = items.reduce(0) { $0 + $1.value }
            let ranks = valueRanks(items)

            var nodes: [Node] = []
            var y: Double = 0
            for (index, item) in items.enumerated() {
                let node = Node(
                    id: item.id,
                    name: item.name,
                    value: item.value,
                    percent: columnTotal > 0 ? item.value / columnTotal * 100 : 0,
                    box: Box(x: xs[column], y: y, width: widthOf(column), height: heights[index]),
                    rank: ranks[index],
                    stage: column
                )
                nodes.append(node)
                nodesByID[item.id] = node
                drawIndexByID[item.id] = index
                heightByID[item.id] = heights[index]
                y += heights[index] + gap
            }
            placed.append(nodes)
        }

        // Only ribbons between adjacent columns, both ends of which survived the
        // filter above.
        let edges = flow.edges.filter { edge in
            guard let source = nodesByID[edge.sourceID], let target = nodesByID[edge.targetID] else {
                return false
            }
            return target.stage == source.stage + 1
        }

        var incoming: [String: [Int]] = [:]
        var outgoing: [String: [Int]] = [:]
        for (index, edge) in edges.enumerated() {
            incoming[edge.targetID, default: []].append(index)
            outgoing[edge.sourceID, default: []].append(index)
        }
        for id in incoming.keys {
            incoming[id]?.sort { (drawIndexByID[edges[$0].sourceID] ?? 0) < (drawIndexByID[edges[$1].sourceID] ?? 0) }
        }
        for id in outgoing.keys {
            outgoing[id]?.sort { (drawIndexByID[edges[$0].targetID] ?? 0) < (drawIndexByID[edges[$1].targetID] ?? 0) }
        }

        var targetSpan = [Double](repeating: 0, count: edges.count)
        var sourceSpan = [Double](repeating: 0, count: edges.count)
        var targetTop = [Double](repeating: 0, count: edges.count)
        var sourceTop = [Double](repeating: 0, count: edges.count)

        for (id, indices) in incoming {
            let height = heightByID[id] ?? 0
            let weight = indices.reduce(0.0) { $0 + (heightByID[edges[$1].sourceID] ?? 0) }
            var y = nodesByID[id]?.box.y ?? 0
            for index in indices {
                let share = weight > 0 ? (heightByID[edges[index].sourceID] ?? 0) / weight : 0
                targetSpan[index] = height * share
                targetTop[index] = y
                y += targetSpan[index]
            }
        }
        for (id, indices) in outgoing {
            let height = heightByID[id] ?? 0
            let weight = indices.reduce(0.0) { $0 + targetSpan[$1] }
            var y = nodesByID[id]?.box.y ?? 0
            for index in indices {
                let share = weight > 0 ? targetSpan[index] / weight : 0
                sourceSpan[index] = height * share
                sourceTop[index] = y
                y += sourceSpan[index]
            }
        }

        let links: [Link] = edges.indices.compactMap { index in
            let edge = edges[index]
            guard let source = nodesByID[edge.sourceID], let target = nodesByID[edge.targetID] else {
                return nil
            }
            return Link(
                id: "link\(idSeparator)\(edge.sourceID)\(idSeparator)\(edge.targetID)",
                sourceID: edge.sourceID,
                targetID: edge.targetID,
                value: edge.value,
                rank: target.rank ?? 0,
                sourceRank: source.rank ?? 0,
                stage: source.stage,
                sourceX: source.box.maxX,
                targetX: target.box.x,
                sourceTop: sourceTop[index],
                sourceBottom: sourceTop[index] + sourceSpan[index],
                targetTop: targetTop[index],
                targetBottom: targetTop[index] + targetSpan[index]
            )
        }

        let total = columns[0].reduce(0) { $0 + $1.value }
        return Diagram(columns: placed, links: links, total: total)
    }

    /// Rank within a column: largest first, name breaking ties, matching the
    /// order `fold` sorts into.
    private static func valueRanks(_ items: [Item]) -> [Int] {
        let order = items.indices.sorted { left, right in
            items[left].value == items[right].value
                ? items[left].name < items[right].name
                : items[left].value > items[right].value
        }
        var ranks = Array(repeating: 0, count: items.count)
        for (rank, index) in order.enumerated() { ranks[index] = rank }
        return ranks
    }

    /// The two-column diagram: a trunk labelled `source`, and one band per
    /// branch. A `Flow` of two columns run through the same engine, so the
    /// folding, the clamp and the ribbon arithmetic can only ever be one
    /// implementation.
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

        let sourceID = "source"
        let ids = bands.enumerated().map { "band.\($0.offset).\($0.element.name)" }
        let flow = Flow(
            stages: [
                Stage([Item(id: sourceID, name: source, value: total)]),
                Stage(zip(ids, bands).map { Item(id: $0, name: $1.name, value: $1.value) }),
            ],
            edges: zip(ids, bands).map { Edge(from: sourceID, to: $0, value: $1.value) }
        )

        let diagram = layout(
            flow,
            geometry: geometry,
            widths: [geometry.sourceWidth, geometry.bandWidth]
        )
        guard diagram.columns.count == 2, let trunk = diagram.columns[0].first else { return .empty }

        // The trunk is one node in its own column, so it fills the box and takes
        // no rank: it is not one of the bands the colour ramp is walking.
        let sourceNode = Node(
            id: trunk.id,
            name: trunk.name,
            value: trunk.value,
            percent: 100,
            box: trunk.box,
            rank: nil,
            stage: 0
        )
        return Layout(
            source: sourceNode,
            bands: diagram.columns[1],
            links: diagram.links,
            total: total
        )
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
