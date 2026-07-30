import XCTest

/// All figures here are synthetic (a fictional ~$1.2M portfolio); this repo is
/// public. Geometry is asserted in the unit box the layout emits, so nothing
/// here depends on a screen size.
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
}
