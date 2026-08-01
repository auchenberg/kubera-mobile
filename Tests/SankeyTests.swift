import XCTest

/// All figures here are synthetic (a fictional ~$1.2M portfolio); this repo is
/// public. Geometry is asserted in the unit box the layout emits, so nothing
/// here depends on a screen size.
///
/// Two entry points are covered: `assetFlow(from:debtTotal:)` with the
/// multi-stage engine behind it, which is what the Overview draws, and the older
/// two-column `layout(source:branches:)`, which is now a wrapper over the same
/// engine — so the tests below are also what says the wrapper still behaves.
final class SankeyTests: XCTestCase {
    private func branch(_ name: String, _ value: Double) -> Sankey.Branch {
        Sankey.Branch(name: name, value: value)
    }

    /// The demo book grouped by sheet, the way `SankeyView` feeds the layout:
    /// `OverviewModules` does the labelling, `Sankey` does the folding. Sums to
    /// 1,610,000 — Investments 860K, Real estate 450K, Crypto 130K, Banks 74K,
    /// Vehicles 62K, Collectibles 34K.
    private var demoBranches: [Sankey.Branch] {
        Sankey.branches(from: DemoData.detail.assets, by: .sheet)
    }

    private let epsilon = 1e-9

    // MARK: - Building branches

    func testBranchesArriveUnfoldedSoOnlySankeysRulesDecideTheTail() {
        // The composition module's own 6-row cap and 3% floor are switched off,
        // or the tail would be folded twice against two different rules and both
        // modules would show an "Other" meaning something different.
        let branches = Sankey.branches(from: DemoData.detail.assets, by: .sheet)

        XCTAssertEqual(branches.count, 6)
        XCTAssertFalse(branches.contains { $0.name == Sankey.otherBandName })
        XCTAssertEqual(branches.reduce(0) { $0 + $1.value }, 1_610_000, accuracy: epsilon)
    }

    func testAssetsWithNoSheetAreLabelledRatherThanDropped() {
        // Unfiled money is still money; losing it would make the trunk disagree
        // with the asset total the rest of the screen prints.
        let assets = [
            PortfolioDetail.Asset(
                name: "Index funds", value: 800_000, assetClass: nil, ticker: nil,
                sheet: "Investments", section: nil
            ),
            PortfolioDetail.Asset(
                name: "Loose ends", value: 200_000, assetClass: nil, ticker: nil,
                sheet: nil, section: nil
            ),
        ]

        let branches = Sankey.branches(from: assets, by: .sheet)

        XCTAssertEqual(branches.map(\.name).sorted(), ["Investments", OverviewModules.unsortedGroupName])
        XCTAssertEqual(branches.reduce(0) { $0 + $1.value }, 1_000_000, accuracy: epsilon)
    }

    func testIsWorthDrawingAgreesWithTheLayoutItWouldProduce() {
        // The screen calls this before printing a section heading, so a
        // disagreement means a heading over an empty space.
        for book in [demoBranches, [], [branch("Only", 1_200_000)]] {
            XCTAssertEqual(
                Sankey.isWorthDrawing(book),
                Sankey.layout(source: "Assets", branches: book).isMeaningful
            )
        }
        XCTAssertTrue(Sankey.isWorthDrawing(demoBranches))
        XCTAssertFalse(Sankey.isWorthDrawing([branch("Only", 1_200_000)]))
    }

    // MARK: - Folding the tail

    func testFoldsBandsUnderTheThresholdIntoOneOther() {
        // 3.8% and 0.9% are ribbons two points thick on a phone; they belong in
        // one band that can carry a label, not in two that cannot. Crypto at
        // 5.7% stays, so the threshold is shown cutting somewhere real.
        let folded = Sankey.fold([
            branch("Investments", 600_000),
            branch("Real estate", 350_000),
            branch("Crypto", 60_000),
            branch("Vehicles", 40_000),
            branch("Collectibles", 10_000),
        ])

        XCTAssertEqual(folded.map(\.name), ["Investments", "Real estate", "Crypto", "Other"])
        XCTAssertEqual(folded.last?.value, 50_000)
    }

    func testFoldsEverythingPastTheBandCapEvenWhenItClearsTheThreshold() {
        // Seven bands each well over the 5% floor still cannot all fit beside a
        // label column, so the cap has to bite independently of the threshold.
        let cap = Sankey.defaultMaximumBands
        let folded = Sankey.fold((1 ... 7).map { branch("Sheet \($0)", Double(8 - $0) * 100_000) })

        XCTAssertEqual(folded.count, cap + 1)
        XCTAssertEqual(
            Array(folded.map(\.name).prefix(cap)),
            (1 ... cap).map { "Sheet \($0)" }
        )
        XCTAssertEqual(folded.last?.name, Sankey.otherBandName)
        // Everything the cap pushed out, and nothing else.
        let expectedTail = ((cap + 1) ... 7).reduce(0.0) { $0 + Double(8 - $1) * 100_000 }
        XCTAssertEqual(folded.last?.value ?? 0, expectedTail, accuracy: epsilon)
    }

    func testAnExistingOtherSheetAbsorbsTheTailInsteadOfGainingATwin() {
        // A user really can name a sheet "Other". Two bands with one name would
        // be two ribbons the reader has no way to tell apart.
        let folded = Sankey.fold([
            branch("Investments", 600_000),
            branch(Sankey.otherBandName, 300_000),
            branch("Crypto", 20_000),
            branch("Vehicles", 10_000),
        ])

        XCTAssertEqual(folded.map(\.name), ["Investments", Sankey.otherBandName])
        XCTAssertEqual(folded.last?.value, 330_000)
        XCTAssertEqual(folded.filter { $0.name == Sankey.otherBandName }.count, 1)
    }

    func testFoldingConservesTheWholePositiveTotal() {
        // The trunk is the sum of the bands. If folding lost a cent the diagram
        // would assert a conservation that does not hold.
        let branches = demoBranches
        let total = branches.reduce(0) { $0 + $1.value }

        XCTAssertEqual(Sankey.fold(branches).reduce(0) { $0 + $1.value }, total, accuracy: epsilon)
        XCTAssertEqual(total, 1_610_000, accuracy: epsilon)
    }

    // MARK: - Ordering

    func testBandsComeOutLargestFirstWithNameBreakingTies() {
        let folded = Sankey.fold([
            branch("Crypto", 200_000),
            branch("Investments", 500_000),
            branch("Banks", 200_000),
            branch("Real estate", 300_000),
        ])

        XCTAssertEqual(folded.map(\.name), ["Investments", "Real estate", "Banks", "Crypto"])
    }

    func testTheSameInputInADifferentOrderProducesIdenticalGeometry() {
        // Kubera's asset list arrives in whatever order the endpoint felt like.
        // A diagram that reshuffles between refreshes is a diagram that flickers.
        let forward = Sankey.layout(source: "Assets", branches: demoBranches)
        let backward = Sankey.layout(source: "Assets", branches: demoBranches.reversed())

        XCTAssertEqual(forward, backward)
    }

    func testTwoRunsOverTheSameInputAreByteIdentical() {
        let first = Sankey.layout(source: "Assets", branches: demoBranches)
        let second = Sankey.layout(source: "Assets", branches: demoBranches)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
    }

    // MARK: - Thickness and the minimum clamp

    func testThicknessesStayProportionalWhenNothingReachesTheFloor() {
        let heights = Sankey.thicknesses([600, 300, 100], available: 1, minimum: 0.05)

        XCTAssertEqual(heights[0], 0.6, accuracy: epsilon)
        XCTAssertEqual(heights[1], 0.3, accuracy: epsilon)
        XCTAssertEqual(heights[2], 0.1, accuracy: epsilon)
    }

    func testASmallBandIsRaisedToTheFloorAndTheLargeOnesPayForIt() {
        // The point of the clamp: 1% of the book is still a real category the
        // reader can see and touch. The large bands lose the difference, which
        // is the stated cost of the trade.
        let heights = Sankey.thicknesses([700, 290, 10], available: 1, minimum: 0.1)

        XCTAssertEqual(heights[2], 0.1, accuracy: epsilon)
        XCTAssertEqual(heights[0], 0.9 * 700 / 990, accuracy: epsilon)
        XCTAssertEqual(heights[1], 0.9 * 290 / 990, accuracy: epsilon)
        XCTAssertGreaterThan(heights[0], heights[1])
    }

    func testSeveralBandsCanClampAtOnceAndTheRemainderStaysProportional() {
        // Two bands under the floor: the second clamp has to be decided against
        // the room the first one already took, not against the original total.
        let heights = Sankey.thicknesses([800, 200, 30, 20], available: 1, minimum: 0.12)

        XCTAssertEqual(heights[2], 0.12, accuracy: epsilon)
        XCTAssertEqual(heights[3], 0.12, accuracy: epsilon)
        XCTAssertEqual(heights[0], 0.76 * 800 / 1_000, accuracy: epsilon)
        XCTAssertEqual(heights[1], 0.76 * 200 / 1_000, accuracy: epsilon)
        // The second band stays clear of the floor, so this really is the
        // "some clamped, the rest still proportional" case and not a coincidence.
        XCTAssertGreaterThan(heights[1], 0.12)
    }

    func testThicknessesAlwaysFillTheAvailableHeightExactly() {
        // Whatever the clamp does, the bands plus the gaps are the box. A
        // rounding drift here shows up as a diagram that stops short of its own
        // frame.
        for minimum in [0.0, 0.02, 0.1, 0.18] {
            for available in [1.0, 0.958, 0.5] {
                let heights = Sankey.thicknesses([860, 450, 130, 74, 62], available: available, minimum: minimum)
                XCTAssertEqual(
                    heights.reduce(0, +),
                    available,
                    accuracy: 1e-12,
                    "minimum \(minimum), available \(available)"
                )
            }
        }
    }

    func testAFloorTooTallForEveryBandSplitsTheHeightEqually() {
        // Six bands at a 20% floor need 120% of the box. Degrading to equal
        // sizes keeps every band visible; honouring the floor for the first few
        // would push the rest off the bottom.
        let heights = Sankey.thicknesses([600, 200, 100, 50, 30, 20], available: 1, minimum: 0.2)

        XCTAssertEqual(Set(heights.map { ($0 * 1e9).rounded() }).count, 1)
        XCTAssertEqual(heights.reduce(0, +), 1, accuracy: epsilon)
    }

    func testAZeroFloorLeavesTheSplitStrictlyProportional() {
        // The escape hatch for a caller that would rather have a hairline than a
        // distorted diagram.
        let heights = Sankey.thicknesses([990, 10], available: 1, minimum: 0)

        XCTAssertEqual(heights[0], 0.99, accuracy: epsilon)
        XCTAssertEqual(heights[1], 0.01, accuracy: epsilon)
    }

    func testALargerBandIsNeverDrawnShorterThanASmallerOne() {
        // The clamp is allowed to flatten the difference between two bands; it
        // is never allowed to invert it. A diagram that draws 5% taller than 15%
        // is worse than no diagram.
        let books = [
            [860.0, 450, 130, 74, 62],
            [990.0, 10],
            [500.0, 490, 5, 3, 2],
            [250.0, 250, 250, 250],
            [1.0, 1, 1, 1, 1, 1],
        ]
        for values in books {
            for minimum in [0.0, 0.05, 0.12, 0.2] {
                let heights = Sankey.thicknesses(values, available: 0.94, minimum: minimum)
                for (left, right) in zip(values.indices, values.indices.dropFirst())
                where values[left] > values[right] {
                    XCTAssertGreaterThanOrEqual(
                        heights[left],
                        heights[right] - 1e-12,
                        "\(values) at floor \(minimum)"
                    )
                }
            }
        }
    }

    func testEqualValuesGetEqualThicknessRatherThanDriftingApart() {
        let heights = Sankey.thicknesses([250, 250, 250, 250], available: 1, minimum: 0.1)

        for height in heights {
            XCTAssertEqual(height, 0.25, accuracy: epsilon)
        }
    }

    // MARK: - Layout geometry

    func testBandsAndGapsTogetherFillTheUnitBox() {
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)
        let gaps = Double(layout.bands.count - 1) * Sankey.Geometry().bandGap

        XCTAssertEqual(layout.bands.reduce(0) { $0 + $1.box.height } + gaps, 1, accuracy: 1e-12)
        XCTAssertEqual(layout.bands.first?.box.y, 0)
        XCTAssertEqual(layout.bands.last?.box.maxY ?? 0, 1, accuracy: 1e-12)
    }

    func testTheTrunkIsContiguousAndSpansTheWholeBox() {
        // No gaps on the trunk side: the money leaving it is not separated, and
        // a gap there would read as a slice of the total that goes nowhere.
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)
        let segments = Sankey.trunkSegments(layout)

        XCTAssertEqual(segments.count, layout.bands.count)
        XCTAssertEqual(segments.first?.y, 0)
        XCTAssertEqual(segments.last?.maxY ?? 0, 1, accuracy: 1e-12)
        for (previous, next) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(previous.maxY, next.y, accuracy: 1e-12)
        }
    }

    func testEveryRibbonMeetsItsTrunkSegmentAndItsBandExactly() {
        // A ribbon that misses its band by a fraction shows as a seam at the
        // node edge, which is the tell of a Sankey drawn by eye.
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)

        for link in layout.links {
            let band = layout.bands.first { $0.id == link.targetID }
            XCTAssertEqual(link.targetTop, band?.box.y ?? -1, accuracy: 1e-12)
            XCTAssertEqual(link.targetBottom, band?.box.maxY ?? -1, accuracy: 1e-12)
            XCTAssertEqual(link.sourceX, layout.source?.box.maxX ?? -1)
            XCTAssertEqual(link.targetX, band?.box.x ?? -1)
        }
    }

    func testRibbonsNarrowTowardsTheBandsRatherThanFlaring() {
        // The trunk is contiguous and the bands are padded, so every ribbon is
        // at least as wide where it leaves as where it lands. A ribbon that
        // flares reads as the flow gaining money in transit.
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)

        for link in layout.links {
            let atSource = link.sourceBottom - link.sourceTop
            let atTarget = link.targetBottom - link.targetTop
            XCTAssertGreaterThanOrEqual(atSource, atTarget - 1e-12, "band \(link.targetID)")
        }
    }

    func testControlPointsSitAtTheHorizontalMidpointOfTheGap() {
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)

        for link in layout.links {
            XCTAssertEqual(link.controlX, (link.sourceX + link.targetX) / 2, accuracy: epsilon)
        }
    }

    func testTheTrunkCarriesTheSumOfTheBandsDrawn() {
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)

        XCTAssertEqual(layout.total, 1_610_000, accuracy: epsilon)
        XCTAssertEqual(layout.source?.value, layout.total)
        XCTAssertEqual(layout.bands.reduce(0) { $0 + $1.value }, layout.total, accuracy: epsilon)
        XCTAssertEqual(layout.bands.reduce(0) { $0 + $1.percent }, 100, accuracy: 1e-9)
    }

    func testTheDemoBookFoldsToFourBandsAndClampsTheTwoSmallest() {
        // The case the module exists for: ten assets over six sheets, which a
        // naive port draws as six ribbons, two of them under 4%.
        let layout = Sankey.layout(source: "Assets", branches: demoBranches)

        XCTAssertEqual(layout.bands.map(\.name), ["Investments", "Real estate", "Crypto", "Other"])
        XCTAssertTrue(layout.isMeaningful)

        let floor = Sankey.Geometry().minimumThickness
        // Crypto is 8.1% and Other 10.6%, both of which land under the floor
        // once the gaps are taken out — so the clamp is doing real work here
        // and the two large bands are a few percent short of proportional.
        XCTAssertEqual(layout.bands[2].box.height, floor, accuracy: epsilon)
        XCTAssertEqual(layout.bands[3].box.height, floor, accuracy: epsilon)
        XCTAssertGreaterThan(layout.bands[0].box.height, layout.bands[0].percent / 100 * 0.9)
        XCTAssertLessThan(layout.bands[0].box.height, layout.bands[0].percent / 100)
    }

    // MARK: - Degenerate input

    func testEmptyInputProducesAnEmptyLayout() {
        let layout = Sankey.layout(source: "Assets", branches: [])

        XCTAssertTrue(layout.isEmpty)
        XCTAssertFalse(layout.isMeaningful)
        XCTAssertNil(layout.source)
        XCTAssertEqual(layout.links.count, 0)
        XCTAssertEqual(layout.total, 0)
        XCTAssertEqual(Sankey.trunkSegments(layout), [])
    }

    func testAZeroTotalProducesAnEmptyLayoutRatherThanDividingByIt() {
        let layout = Sankey.layout(source: "Assets", branches: [
            branch("Investments", 0),
            branch("Crypto", 0),
        ])

        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.total, 0)
    }

    func testNegativeBranchesAreDroppedRatherThanDrawnAsWidth() {
        // A debt carried as a negative has no ribbon thickness, and letting it
        // in would make the trunk disagree with the bands hanging off it.
        let layout = Sankey.layout(source: "Assets", branches: [
            branch("Investments", 800_000),
            branch("Real estate", 400_000),
            branch("Mortgage", -300_000),
        ])

        XCTAssertEqual(layout.bands.map(\.name), ["Investments", "Real estate"])
        XCTAssertEqual(layout.total, 1_200_000, accuracy: epsilon)
    }

    func testAnAllNegativeBookProducesAnEmptyLayout() {
        let layout = Sankey.layout(source: "Debts", branches: [
            branch("Mortgage", -300_000),
            branch("Car loan", -70_000),
        ])

        XCTAssertTrue(layout.isEmpty)
        XCTAssertFalse(layout.isMeaningful)
    }

    func testNonFiniteValuesAreDroppedBeforeTheyPoisonTheGeometry() {
        // One NaN in the input would make every band's height NaN and the
        // diagram would silently vanish.
        let layout = Sankey.layout(source: "Assets", branches: [
            branch("Investments", 800_000),
            branch("Glitch", .nan),
            branch("Runaway", .infinity),
        ])

        XCTAssertEqual(layout.bands.map(\.name), ["Investments"])
        XCTAssertEqual(layout.total, 800_000, accuracy: epsilon)
    }

    func testASingleBandFillsTheBoxButDoesNotEarnADiagram() {
        // "All of it is in one sheet" is a sentence, not a flow. The view checks
        // `isMeaningful` and shows the list instead.
        let layout = Sankey.layout(source: "Assets", branches: [branch("Investments", 1_200_000)])

        XCTAssertFalse(layout.isEmpty)
        XCTAssertFalse(layout.isMeaningful)
        XCTAssertEqual(layout.bands.first?.box.height, 1)
        XCTAssertEqual(layout.bands.first?.percent, 100)
        XCTAssertEqual(layout.links.first?.sourceTop, 0)
        XCTAssertEqual(layout.links.first?.sourceBottom, 1)
    }

    func testAnAbsurdGapCannotSwallowMoreThanHalfTheBox() {
        // Nothing passes a gap this large today, but a geometry that can produce
        // negative band heights is one refactor away from an inverted ribbon.
        let layout = Sankey.layout(
            source: "Assets",
            branches: demoBranches,
            geometry: Sankey.Geometry(bandGap: 5)
        )

        XCTAssertEqual(layout.bands.reduce(0) { $0 + $1.box.height }, 0.5, accuracy: 1e-12)
        for band in layout.bands {
            XCTAssertGreaterThan(band.box.height, 0)
        }
    }

    func testNoDegenerateGeometryEverProducesANaNOrANegativeHeight() {
        let geometries = [
            Sankey.Geometry(),
            Sankey.Geometry(sourceWidth: 0, bandWidth: 0, bandGap: 0, minimumThickness: 0),
            Sankey.Geometry(sourceWidth: -1, bandWidth: -1, bandGap: -1, minimumThickness: -1),
            Sankey.Geometry(sourceWidth: 9, bandWidth: 9, bandGap: 0.4, minimumThickness: 9),
        ]
        let books: [[Sankey.Branch]] = [
            [],
            [branch("Only", 1)],
            [branch("A", 0), branch("B", 0)],
            demoBranches,
            (1 ... 12).map { branch("Sheet \($0)", Double(13 - $0)) },
        ]

        for geometry in geometries {
            for book in books {
                let layout = Sankey.layout(source: "Assets", branches: book, geometry: geometry)
                for band in layout.bands {
                    XCTAssertFalse(band.box.height.isNaN)
                    XCTAssertFalse(band.box.y.isNaN)
                    XCTAssertGreaterThanOrEqual(band.box.height, 0)
                    XCTAssertGreaterThanOrEqual(band.box.width, 0)
                    XCTAssertLessThanOrEqual(band.box.maxY, 1 + 1e-12)
                }
                for link in layout.links {
                    XCTAssertGreaterThanOrEqual(link.sourceBottom - link.sourceTop, -1e-12)
                    XCTAssertGreaterThanOrEqual(link.targetBottom - link.targetTop, -1e-12)
                    XCTAssertFalse(link.controlX.isNaN)
                }
            }
        }
    }

    // MARK: - The Overview's asset flow

    private func asset(
        _ name: String,
        _ value: Double,
        sheet: String? = nil,
        section: String? = nil
    ) -> PortfolioDetail.Asset {
        PortfolioDetail.Asset(
            name: name, value: value, assetClass: nil, ticker: nil, sheet: sheet, section: section
        )
    }

    private func columnSums(_ flow: Sankey.Flow) -> [Double] {
        flow.stages.map { $0.items.reduce(0) { $0 + $1.value } }
    }

    /// The demo book with its sheets, sections and debts — the flow the Overview
    /// actually draws.
    private var demoFlow: Sankey.Flow {
        Sankey.assetFlow(from: DemoData.detail.assets, debtTotal: 370_000)
    }

    /// Seven sheets of five sections each: past every cap this module has.
    private var crowdedBook: [PortfolioDetail.Asset] {
        (1 ... 7).flatMap { sheet in
            (1 ... 5).map { section in
                asset(
                    "a\(sheet)\(section)",
                    Double((8 - sheet) * 1_000 + section * 37),
                    sheet: "Sheet \(sheet)",
                    section: "Sec \(section)"
                )
            }
        }
    }

    func testEveryColumnOfTheFlowCarriesTheSameTotal() {
        // The whole claim of a Sankey. Sections sum to their sheet, sheets to
        // Assets, and Assets to net worth plus debts; a column that disagrees is
        // a diagram asserting money appeared or vanished mid-picture.
        for flow in [demoFlow, Sankey.assetFlow(from: crowdedBook, debtTotal: 5_000)] {
            let sums = columnSums(flow)
            XCTAssertGreaterThanOrEqual(sums.count, 3)
            for sum in sums {
                XCTAssertEqual(sum, sums[0], accuracy: 1e-6)
            }
        }
        XCTAssertEqual(columnSums(demoFlow)[0], 1_610_000, accuracy: epsilon)
    }

    func testTheDemoBookRunsSectionsThroughSheetsIntoAssetsAndBackOut() {
        let flow = demoFlow

        XCTAssertEqual(flow.stages.count, 4)
        XCTAssertEqual(
            flow.stages[1].items.map(\.name),
            ["Investments", "Real estate", "Crypto", Sankey.otherBandName]
        )
        XCTAssertEqual(flow.stages[2].items.map(\.name), [Sankey.assetsNodeName])
        XCTAssertEqual(
            flow.stages[3].items.map(\.name),
            [Sankey.netWorthNodeName, Sankey.debtsNodeName]
        )
        XCTAssertTrue(flow.isMeaningful)
        XCTAssertEqual(flow.trunk?.value, 1_610_000)
    }

    func testASectionNameSharedByTwoSheetsStaysTwoLeaves() {
        // Both sheets are allowed an "Equity" section and they are two different
        // piles of money. Keyed by name alone they would merge into one leaf
        // feeding two sheets, which is a shape this diagram cannot read.
        let flow = Sankey.assetFlow(
            from: [
                asset("A", 100, sheet: "One", section: "Equity"),
                asset("B", 60, sheet: "Two", section: "Equity"),
            ],
            debtTotal: 0
        )

        let leaves = flow.stages[0].items
        XCTAssertEqual(leaves.map(\.name), ["Equity", "Equity"])
        XCTAssertEqual(Set(leaves.map(\.id)).count, 2)
        XCTAssertEqual(leaves.map(\.value), [100, 60])
        // And each still feeds its own sheet.
        XCTAssertEqual(Set(flow.edges.filter { $0.sourceID == leaves[0].id }.map(\.targetID)).count, 1)
    }

    func testUnfiledAssetsAreParkedRatherThanDropped() {
        // Unfiled money is still money; losing it would make the Assets node
        // disagree with the asset total the rest of the screen prints.
        let flow = Sankey.assetFlow(
            from: [
                asset("Index funds", 800_000, sheet: "Investments", section: "Taxable"),
                asset("Loose ends", 200_000),
            ],
            debtTotal: 0
        )

        XCTAssertTrue(flow.stages[1].items.map(\.name).contains(OverviewModules.unsortedGroupName))
        XCTAssertTrue(flow.stages[0].items.map(\.name).contains(OverviewModules.unsortedGroupName))
        XCTAssertEqual(columnSums(flow)[0], 1_000_000, accuracy: epsilon)
    }

    func testTheLeafColumnStaysInsideItsCapHoweverManySectionsThereAre() {
        // The canvas grows sideways but not downwards, so this cap is what keeps
        // the leaf labels from touching. Seven sheets of five sections is 35
        // candidates.
        let flow = Sankey.assetFlow(from: crowdedBook, debtTotal: 5_000)

        XCTAssertEqual(flow.stages[0].items.count, Sankey.defaultMaximumLeaves)
        XCTAssertLessThanOrEqual(flow.stages[1].items.count, Sankey.defaultMaximumBands + 1)
        // The budget is shared out, so no sheet takes the whole allowance.
        for sheet in flow.stages[1].items {
            let leaves = flow.edges.filter { $0.targetID == sheet.id }
            XCTAssertGreaterThanOrEqual(leaves.count, 1)
            XCTAssertLessThanOrEqual(leaves.count, 3)
        }
    }

    func testEachSheetFoldsItsOwnTailRatherThanSharingOne() {
        // Two sheets, each with a long tail. One shared "Other" would draw a
        // leaf feeding two sheets; each sheet's own tail is a leaf that reads as
        // "Investments / Other".
        // A heavy head and five slivers under the 5% threshold, on both sheets.
        let tail: [Double] = [1_000, 100, 50, 30, 20, 10]
        var book: [PortfolioDetail.Asset] = []
        for (index, value) in tail.enumerated() {
            let section = "S\(index)"
            book.append(asset("i\(index)", value * 2, sheet: "Investments", section: section))
            book.append(asset("b\(index)", value, sheet: "Banks", section: section))
        }
        let flow = Sankey.assetFlow(from: book, debtTotal: 0)

        let others = flow.stages[0].items.filter { $0.name == Sankey.otherBandName }
        XCTAssertEqual(others.count, 2)
        XCTAssertEqual(Set(others.map(\.id)).count, 2)
        for other in others {
            XCTAssertEqual(flow.edges.filter { $0.sourceID == other.id }.count, 1)
        }
    }

    func testTheFoldedSheetTailIsBrokenDownByTheSheetsItSwallowed() {
        // "Other" here is a group of sheets, so its leaves name those sheets.
        // Breaking it down by section instead would print four section names
        // under a heading that says nothing about where they came from.
        let flow = demoFlow
        guard let other = flow.stages[1].items.first(where: { $0.name == Sankey.otherBandName }) else {
            return XCTFail("the demo book's tail sheets should fold")
        }

        let leaves = flow.edges
            .filter { $0.targetID == other.id }
            .compactMap { edge in flow.stages[0].items.first { $0.id == edge.sourceID } }

        XCTAssertEqual(Set(leaves.map(\.name)), ["Banks", "Vehicles", "Collectibles"])
        XCTAssertEqual(leaves.map(\.value), leaves.map(\.value).sorted(by: >))
        XCTAssertEqual(leaves.reduce(0) { $0 + $1.value }, other.value, accuracy: epsilon)
    }

    func testDebtsLeaveAssetsBesideNetWorthAndTheTwoSumBack() {
        let flow = demoFlow
        let outflows = flow.stages[3].items

        XCTAssertEqual(outflows.reduce(0) { $0 + $1.value }, 1_610_000, accuracy: epsilon)
        XCTAssertEqual(outflows.first { $0.name == Sankey.debtsNodeName }?.value, 370_000)
        XCTAssertEqual(outflows.first { $0.name == Sankey.netWorthNodeName }?.value, 1_240_000)
        // Largest first, so net worth sits on top and the debt outflow at the
        // bottom right.
        XCTAssertEqual(outflows.first?.name, Sankey.netWorthNodeName)
    }

    func testWithoutDebtsTheFlowEndsAtAssets() {
        // Net worth would equal Assets, and a column that repeats the one before
        // it costs width to say nothing.
        for debts in [0.0, -50_000, Double.nan] {
            let flow = Sankey.assetFlow(from: DemoData.detail.assets, debtTotal: debts)

            XCTAssertEqual(flow.stages.count, 3, "debts \(debts)")
            XCTAssertEqual(flow.stages.last?.items.map(\.name), [Sankey.assetsNodeName])
            XCTAssertEqual(columnSums(flow).last, 1_610_000)
        }
    }

    func testANegativeNetWorthFallsBackToEndingAtAssets() {
        // A ribbon's width is a magnitude, so an outflow pair that has to sum to
        // less than one of its own members cannot be drawn. Ending at Assets is
        // still true; the cards above carry the negative figure.
        let flow = Sankey.assetFlow(from: DemoData.detail.assets, debtTotal: 2_000_000)

        XCTAssertEqual(flow.stages.count, 3)
        XCTAssertEqual(flow.stages.last?.items.map(\.name), [Sankey.assetsNodeName])
    }

    func testSheetsComeLargestFirstAndTheirLeavesFollowThem() {
        // Leaves grouped under their sheet's span is what keeps the fan from
        // crossing itself; ordering both levels by value keeps it monotonic
        // inside each group.
        let flow = demoFlow
        let sheets = flow.stages[1].items

        // The named sheets descend. "Other" is last whatever it weighs — it is
        // the leftover bucket, and `fold` puts it at the bottom on purpose, so
        // it is excluded from the descent rather than sorted into it.
        let named = sheets.filter { $0.name != Sankey.otherBandName }
        XCTAssertEqual(named.map(\.value), named.map(\.value).sorted(by: >))
        XCTAssertEqual(sheets.last?.name, Sankey.otherBandName)

        // Every leaf's parent, in leaf order, must run through the sheets in
        // sheet order without ever coming back to an earlier one.
        let parents = flow.stages[0].items.map { leaf in
            flow.edges.first { $0.sourceID == leaf.id }?.targetID ?? ""
        }
        var seen: [String] = []
        for parent in parents where seen.last != parent {
            XCTAssertFalse(seen.contains(parent), "leaves of \(parent) are split apart")
            seen.append(parent)
        }
        XCTAssertEqual(seen, sheets.map(\.id))

        // And within one sheet the sections descend.
        for sheet in sheets {
            let values = flow.edges.filter { $0.targetID == sheet.id }.map(\.value)
            XCTAssertEqual(values, values.sorted(by: >))
        }
    }

    func testALeafColumnOfNothingButUnsortedIsDropped() {
        // A book with no sections at all would draw a first column of identical
        // "Unsorted" labels restating the sheets beside them.
        let book = DemoData.detail.assets.map {
            asset($0.name, $0.value, sheet: $0.sheet, section: nil)
        }
        let flow = Sankey.assetFlow(from: book, debtTotal: 370_000)

        XCTAssertEqual(flow.stages.count, 3)
        XCTAssertEqual(flow.stages[0].items.map(\.name).first, "Investments")
        XCTAssertEqual(columnSums(flow)[0], 1_610_000, accuracy: epsilon)
    }

    func testASingleSheetDoesNotGetAColumnThatRepeatsAssets() {
        let flow = Sankey.assetFlow(
            from: [
                asset("A", 100, sheet: "Investments", section: "Taxable"),
                asset("B", 60, sheet: "Investments", section: "Retirement"),
            ],
            debtTotal: 40
        )

        XCTAssertEqual(flow.stages.count, 3)
        XCTAssertEqual(flow.stages[0].items.map(\.name), ["Taxable", "Retirement"])
        XCTAssertEqual(flow.stages[1].items.map(\.name), [Sankey.assetsNodeName])
        XCTAssertTrue(flow.isMeaningful)
    }

    func testAFlowWithNothingToBreakDownIsNotWorthDrawing() {
        // One sheet, one section, and a debt: the last column splits but no
        // column before it does, which is two facts rather than a flow.
        let flow = Sankey.assetFlow(
            from: [asset("A", 100, sheet: "Investments", section: "Taxable")],
            debtTotal: 40
        )

        XCTAssertFalse(flow.isMeaningful)
        XCTAssertFalse(Sankey.assetFlow(from: [], debtTotal: 40).isMeaningful)
        XCTAssertTrue(Sankey.assetFlow(from: [], debtTotal: 40).isEmpty)
    }

    func testTheSameBookInADifferentOrderProducesAnIdenticalFlow() {
        // Kubera's asset list arrives in whatever order the endpoint felt like.
        // A diagram that reshuffles between refreshes is a diagram that flickers.
        let forward = Sankey.assetFlow(from: DemoData.detail.assets, debtTotal: 370_000)
        let backward = Sankey.assetFlow(from: DemoData.detail.assets.reversed(), debtTotal: 370_000)

        XCTAssertEqual(forward, backward)
        XCTAssertEqual(
            Sankey.layout(forward, geometry: geometry),
            Sankey.layout(backward, geometry: geometry)
        )
    }

    // MARK: - Multi-stage geometry

    /// A floor a labelled column would really ask for: 24 points of a 320pt card.
    private var geometry: Sankey.Geometry {
        Sankey.Geometry(minimumThickness: 24.0 / 320.0)
    }

    func testEveryColumnFillsTheBoxTopToBottom() {
        // Conservation made visible: the leaves, the sheets, Assets and the
        // outflows are the same total drawn four ways, so they are the same
        // height. A column that stopped short would read as money going nowhere.
        let diagram = Sankey.layout(demoFlow, geometry: geometry)

        for column in diagram.columns {
            XCTAssertEqual(column.first?.box.y ?? -1, 0, accuracy: 1e-12)
            XCTAssertEqual(column.last?.box.maxY ?? -1, 1, accuracy: 1e-12)
            for (above, below) in zip(column, column.dropFirst()) {
                XCTAssertLessThanOrEqual(above.box.maxY, below.box.y + 1e-12)
            }
        }
    }

    func testEveryBoxStaysInsideTheUnitBox() {
        let books: [(book: [PortfolioDetail.Asset], debts: Double)] = [
            (DemoData.detail.assets, 370_000),
            (DemoData.detail.assets, 0),
            (crowdedBook, 5_000),
        ]
        let geometries = [
            Sankey.Geometry(),
            geometry,
            Sankey.Geometry(sourceWidth: 0, bandWidth: 0, bandGap: 0, minimumThickness: 0),
            Sankey.Geometry(sourceWidth: 9, bandWidth: 9, bandGap: 4, minimumThickness: 9),
        ]

        for (book, debts) in books {
            for candidate in geometries {
                let diagram = Sankey.layout(
                    Sankey.assetFlow(from: book, debtTotal: debts),
                    geometry: candidate
                )
                for node in diagram.nodes {
                    XCTAssertFalse(node.box.y.isNaN)
                    XCTAssertFalse(node.box.height.isNaN)
                    XCTAssertGreaterThanOrEqual(node.box.x, 0)
                    XCTAssertGreaterThanOrEqual(node.box.y, -1e-12)
                    XCTAssertGreaterThanOrEqual(node.box.height, 0)
                    XCTAssertLessThanOrEqual(node.box.maxX, 1 + 1e-12)
                    XCTAssertLessThanOrEqual(node.box.maxY, 1 + 1e-12)
                }
                for link in diagram.links {
                    XCTAssertFalse(link.controlX.isNaN)
                    XCTAssertGreaterThanOrEqual(link.sourceBottom - link.sourceTop, -1e-12)
                    XCTAssertGreaterThanOrEqual(link.targetBottom - link.targetTop, -1e-12)
                }
            }
        }
    }

    func testEveryRibbonMeetsTheNodesItJoinsExactly() {
        // A ribbon that misses its node by a fraction shows as a seam at the bar
        // edge, which is the tell of a Sankey drawn by eye.
        let diagram = Sankey.layout(demoFlow, geometry: geometry)
        let nodes = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })

        XCTAssertEqual(diagram.links.count, demoFlow.edges.count)
        XCTAssertGreaterThan(diagram.links.count, 0)
        for link in diagram.links {
            guard let source = nodes[link.sourceID], let target = nodes[link.targetID] else {
                return XCTFail("link \(link.id) joins a node that is not drawn")
            }
            XCTAssertEqual(link.sourceX, source.box.maxX)
            XCTAssertEqual(link.targetX, target.box.x)
            XCTAssertEqual(target.stage, source.stage + 1)
            XCTAssertGreaterThanOrEqual(link.sourceTop, source.box.y - 1e-12)
            XCTAssertLessThanOrEqual(link.sourceBottom, source.box.maxY + 1e-12)
            XCTAssertGreaterThanOrEqual(link.targetTop, target.box.y - 1e-12)
            XCTAssertLessThanOrEqual(link.targetBottom, target.box.maxY + 1e-12)
            XCTAssertEqual(link.controlX, (link.sourceX + link.targetX) / 2, accuracy: epsilon)
        }
    }

    func testRibbonsCoverEachNodeFaceExactlyAndInOrder() {
        // Both faces of every node are fully spoken for: a gap on a face would
        // read as a slice of the flow that arrived from nowhere, and an overlap
        // as one counted twice.
        let diagram = Sankey.layout(demoFlow, geometry: geometry)

        for node in diagram.nodes {
            let outgoing = diagram.links.filter { $0.sourceID == node.id }
            if !outgoing.isEmpty {
                let sorted = outgoing.sorted { $0.sourceTop < $1.sourceTop }
                XCTAssertEqual(sorted.first?.sourceTop ?? -1, node.box.y, accuracy: 1e-12)
                XCTAssertEqual(sorted.last?.sourceBottom ?? -1, node.box.maxY, accuracy: 1e-12)
                for (above, below) in zip(sorted, sorted.dropFirst()) {
                    XCTAssertEqual(above.sourceBottom, below.sourceTop, accuracy: 1e-12)
                }
            }
            let incoming = diagram.links.filter { $0.targetID == node.id }
            if !incoming.isEmpty {
                let sorted = incoming.sorted { $0.targetTop < $1.targetTop }
                XCTAssertEqual(sorted.first?.targetTop ?? -1, node.box.y, accuracy: 1e-12)
                XCTAssertEqual(sorted.last?.targetBottom ?? -1, node.box.maxY, accuracy: 1e-12)
                for (above, below) in zip(sorted, sorted.dropFirst()) {
                    XCTAssertEqual(above.targetBottom, below.targetTop, accuracy: 1e-12)
                }
            }
        }
    }

    func testColumnsAreEvenlySpacedAndTheLastOneEndsOnTheRightEdge() {
        let diagram = Sankey.layout(demoFlow, geometry: geometry)
        let xs = diagram.columns.compactMap { $0.first?.box.x }

        XCTAssertEqual(xs.count, 4)
        XCTAssertEqual(xs.first, 0)
        XCTAssertEqual(diagram.columns.last?.first?.box.maxX ?? 0, 1, accuracy: 1e-12)
        let steps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        for step in steps {
            XCTAssertEqual(step, steps[0], accuracy: 1e-12)
        }
    }

    func testACrowdedColumnGetsALowerFloorRatherThanBeingFlattened() {
        // Twelve leaves at a 24pt floor need more than the whole box, and
        // `thicknesses` would answer that by making every leaf the same height —
        // a column that states something false. The engine lowers the floor to
        // `maximumFloorShare` of the column instead, so the leaves stay ordered.
        let diagram = Sankey.layout(
            Sankey.assetFlow(from: crowdedBook, debtTotal: 5_000),
            geometry: Sankey.Geometry(minimumThickness: 0.4)
        )
        let leaves = diagram.columns[0]

        XCTAssertEqual(leaves.count, 12)
        let floors = leaves.map(\.box.height).reduce(0, +)
        XCTAssertLessThanOrEqual(floors, 1 + 1e-12)
        XCTAssertGreaterThan(Set(leaves.map { ($0.box.height * 1e6).rounded() }).count, 1)
        // The largest leaf is still drawn at least as tall as the smallest.
        let largest = leaves.max { $0.value < $1.value }
        let smallest = leaves.min { $0.value < $1.value }
        XCTAssertGreaterThanOrEqual(largest?.box.height ?? 0, smallest?.box.height ?? 1)
    }

    func testTheTrunkIsTheColumnThatHoldsTheWholeFlowInOneBar() {
        let diagram = Sankey.layout(demoFlow, geometry: geometry)

        XCTAssertEqual(diagram.trunk?.name, Sankey.assetsNodeName)
        XCTAssertEqual(diagram.trunk?.box.height ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(diagram.trunk?.percent, 100)
        XCTAssertEqual(diagram.total, 1_610_000, accuracy: epsilon)
        // The legend level is the column feeding the trunk — the sheets.
        XCTAssertEqual(
            diagram.summaryColumn.map(\.name),
            ["Investments", "Real estate", "Crypto", Sankey.otherBandName]
        )
    }

    func testRanksRestartPerColumnAndFollowValueNotDrawOrder() {
        // The colour ramp is indexed by rank, and the leaves are drawn grouped
        // under their sheet rather than in value order, so a small leaf of a big
        // sheet must still take the paler tone.
        let diagram = Sankey.layout(demoFlow, geometry: geometry)

        for column in diagram.columns {
            XCTAssertEqual(Set(column.compactMap(\.rank)).count, column.count)
            let byRank = column.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }
            XCTAssertEqual(byRank.map(\.value), column.map(\.value).sorted(by: >))
        }
        XCTAssertEqual(diagram.columns[2].first?.rank, 0)
    }

    func testEveryPercentIsAShareOfTheWholeFlow() {
        let diagram = Sankey.layout(demoFlow, geometry: geometry)

        for column in diagram.columns {
            XCTAssertEqual(column.reduce(0) { $0 + $1.percent }, 100, accuracy: 1e-9)
            for node in column {
                XCTAssertEqual(node.percent, node.value / diagram.total * 100, accuracy: 1e-9)
            }
        }
    }

    func testAnEmptyBookProducesAnEmptyDiagramRatherThanDividingByZero() {
        XCTAssertTrue(Sankey.layout(.empty).isEmpty)
        XCTAssertFalse(Sankey.layout(.empty).isMeaningful)
        XCTAssertEqual(Sankey.layout(.empty).total, 0)
        XCTAssertTrue(Sankey.assetFlow(from: [asset("A", 0, sheet: "S")], debtTotal: 0).isEmpty)
        XCTAssertTrue(Sankey.assetFlow(from: [asset("A", .nan, sheet: "S")], debtTotal: 0).isEmpty)
    }

    // MARK: - Folding to a hard ceiling

    func testFoldingIntoALimitCountsOtherInsideIt() {
        // The leaf column's cap is a statement about how many rows fit in a
        // fixed height, so the tail has to come out of the allowance rather than
        // being added on top of it.
        let branches = (1 ... 7).map { branch("Sheet \($0)", Double(8 - $0) * 100_000) }

        for limit in 1 ... 6 {
            let folded = Sankey.fold(branches, into: limit)
            XCTAssertLessThanOrEqual(folded.count, limit, "limit \(limit)")
            XCTAssertEqual(
                folded.reduce(0) { $0 + $1.value },
                branches.reduce(0) { $0 + $1.value },
                accuracy: epsilon,
                "limit \(limit)"
            )
        }
        XCTAssertEqual(Sankey.fold(branches, into: 0), [])
    }

    func testFoldingIntoALimitLeavesAShortListAlone() {
        let branches = [branch("Investments", 600_000), branch("Real estate", 400_000)]

        XCTAssertEqual(Sankey.fold(branches, into: 4), branches)
    }
}
