import XCTest

/// Every figure here is synthetic (a fictional portfolio); this repo is public.
///
/// The suite pins three decisions `AssetBook` makes that the screen cannot make
/// for itself:
///
/// - Nothing is dropped, so the sheet totals always sum to the portfolio's asset
///   side and a section footer always sums its own rows.
/// - Zero and negative assets stay in the table. Kubera lists them, they are
///   part of the total the footer prints, and a table whose rows do not add up
///   to its own footer is one the reader cannot check. This is deliberately
///   unlike `OverviewModules.composition`, which drops non-positive groups
///   because a negative share of a whole is not a share.
/// - Ranking is by value with the name breaking ties, at all three levels, so
///   the same portfolio always renders in the same order.
final class AssetBookTests: XCTestCase {
    private func asset(
        _ name: String,
        _ value: Double,
        sheet: String? = nil,
        section: String? = nil
    ) -> PortfolioDetail.Asset {
        PortfolioDetail.Asset(
            name: name,
            value: value,
            assetClass: nil,
            ticker: nil,
            sheet: sheet,
            section: section
        )
    }

    /// A portfolio whose asset side is exactly what its holdings add up to, so
    /// "the book totals the asset side" is a real assertion rather than a
    /// restatement of the same sum.
    private func detail(_ assets: [PortfolioDetail.Asset]) -> PortfolioDetail {
        PortfolioDetail(
            currency: "USD",
            netWorth: nil,
            assetTotal: assets.reduce(0) { $0 + $1.value },
            debtTotal: nil,
            cashOnHand: nil,
            estimatedTax: nil,
            investableTotal: nil,
            costBasis: nil,
            unrealizedGain: nil,
            assets: assets,
            updatedAt: 0
        )
    }

    private let sample: [PortfolioDetail.Asset] = [
        .init(name: "Index funds", value: 430_000, assetClass: nil, ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "Growth fund", value: 190_000, assetClass: nil, ticker: nil, sheet: "Investments", section: "Taxable"),
        .init(name: "Retirement", value: 240_000, assetClass: nil, ticker: nil, sheet: "Investments", section: "Retirement"),
        .init(name: "Checking", value: 48_000, assetClass: nil, ticker: nil, sheet: "Cash", section: "Everyday"),
        .init(name: "Savings", value: 26_000, assetClass: nil, ticker: nil, sheet: "Cash", section: "Reserve"),
    ]

    // MARK: - Totals

    func testSheetTotalsSumToThePortfoliosAssetSide() {
        let portfolio = detail(sample)
        let book = AssetBook(portfolio)

        XCTAssertEqual(book.total, portfolio.assetTotal!, accuracy: 0.001)
        XCTAssertEqual(book.sheets.reduce(0) { $0 + $1.total }, portfolio.assetTotal!, accuracy: 0.001)
    }

    func testEachSheetTotalsItsOwnSections() {
        for sheet in AssetBook(detail(sample)).sheets {
            XCTAssertEqual(
                sheet.total,
                sheet.sections.reduce(0) { $0 + $1.total },
                accuracy: 0.001,
                "\(sheet.name) does not sum its sections"
            )
        }
    }

    func testEachSectionTotalsItsOwnRows() {
        for sheet in AssetBook(detail(sample)).sheets {
            for section in sheet.sections {
                XCTAssertEqual(
                    section.total,
                    section.rows.reduce(0) { $0 + $1.value },
                    accuracy: 0.001,
                    "\(section.name) does not sum its rows"
                )
            }
        }
    }

    func testEveryAssetLandsInExactlyOneRow() {
        let book = AssetBook(assets: sample + [asset("Unfiled", 1_000)])
        let rows = book.sheets.flatMap { $0.sections.flatMap(\.rows) }

        XCTAssertEqual(rows.count, sample.count + 1)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "row ids must be unique across the book")
    }

    // MARK: - Unsorted parking

    func testAssetsWithNoSheetOrSectionAreParkedUnderUnsorted() {
        let book = AssetBook(assets: [asset("Unfiled", 5_000)])

        XCTAssertEqual(book.sheets.map(\.name), [OverviewModules.unsortedGroupName])
        XCTAssertEqual(book.sheets[0].sections.map(\.name), [OverviewModules.unsortedGroupName])
        XCTAssertEqual(book.sheets[0].sections[0].rows.map(\.name), ["Unfiled"])
    }

    func testBlankAndWhitespaceLabelsParkTheSameWayAsMissingOnes() {
        let book = AssetBook(assets: [
            asset("Nil both", 1_000),
            asset("Empty both", 1_000, sheet: "", section: ""),
            asset("Whitespace both", 1_000, sheet: "   ", section: "\n\t "),
        ])

        XCTAssertEqual(book.sheets.count, 1)
        XCTAssertEqual(book.sheets[0].name, OverviewModules.unsortedGroupName)
        XCTAssertEqual(book.sheets[0].sections.count, 1)
        XCTAssertEqual(book.sheets[0].sections[0].rows.count, 3)
        XCTAssertEqual(book.total, 3_000, accuracy: 0.001)
    }

    /// A sheet with a section missing keeps its own name and parks only the
    /// level that is absent — the asset is filed, just not all the way down.
    func testOnlyTheMissingLevelIsParked() {
        let book = AssetBook(assets: [asset("Car", 62_000, sheet: "Vehicles", section: nil)])

        XCTAssertEqual(book.sheets.map(\.name), ["Vehicles"])
        XCTAssertEqual(book.sheets[0].sections.map(\.name), [OverviewModules.unsortedGroupName])
    }

    func testLabelsAreTrimmedBeforeGrouping() {
        let book = AssetBook(assets: [
            asset("A", 10, sheet: "Investments", section: "Taxable"),
            asset("B", 10, sheet: "  Investments  ", section: " Taxable\n"),
        ])

        XCTAssertEqual(book.sheets.count, 1, "the two spellings are one sheet")
        XCTAssertEqual(book.sheets[0].name, "Investments")
        XCTAssertEqual(book.sheets[0].sections.count, 1)
        XCTAssertEqual(book.sheets[0].sections[0].name, "Taxable")
        XCTAssertEqual(book.sheets[0].sections[0].rows.count, 2)
    }

    /// An unfiled asset is ranked on its total like any other group rather than
    /// pinned to the end: it is real money, and a large unfiled balance is
    /// exactly the thing the reader should see first.
    func testUnsortedIsRankedByTotalLikeAnyOtherSheet() {
        let book = AssetBook(assets: [
            asset("Unfiled", 900_000),
            asset("Checking", 48_000, sheet: "Cash", section: "Everyday"),
        ])

        XCTAssertEqual(book.sheets.map(\.name), [OverviewModules.unsortedGroupName, "Cash"])
    }

    // MARK: - Ordering

    func testSheetsAreRankedByTotalDescending() {
        XCTAssertEqual(AssetBook(detail(sample)).sheets.map(\.name), ["Investments", "Cash"])
    }

    func testSheetsWithEqualTotalsAreOrderedByName() {
        let book = AssetBook(assets: [
            asset("A", 100, sheet: "Zebra", section: "One"),
            asset("B", 100, sheet: "Alpha", section: "One"),
            asset("C", 100, sheet: "Mango", section: "One"),
        ])

        XCTAssertEqual(book.sheets.map(\.name), ["Alpha", "Mango", "Zebra"])
    }

    func testSectionsAreRankedByTotalDescendingThenByName() {
        let book = AssetBook(assets: [
            asset("A", 10, sheet: "S", section: "Small"),
            asset("B", 90, sheet: "S", section: "Large"),
            asset("C", 10, sheet: "S", section: "Also small"),
        ])

        XCTAssertEqual(book.sheets[0].sections.map(\.name), ["Large", "Also small", "Small"])
    }

    func testAssetsAreRankedByValueDescendingThenByName() {
        let book = AssetBook(assets: [
            asset("Middle", 50, sheet: "S", section: "T"),
            asset("Zeta", 100, sheet: "S", section: "T"),
            asset("Alpha", 100, sheet: "S", section: "T"),
        ])

        XCTAssertEqual(book.sheets[0].sections[0].rows.map(\.name), ["Alpha", "Zeta", "Middle"])
    }

    // MARK: - Degenerate books

    func testEmptyBook() {
        let book = AssetBook(assets: [])

        XCTAssertTrue(book.isEmpty)
        XCTAssertTrue(book.sheets.isEmpty)
        XCTAssertEqual(book.total, 0)
        XCTAssertNil(book.sheet(id: nil))
        XCTAssertNil(book.sheet(id: "Investments"))
    }

    func testNilDetailBuildsTheEmptyBook() {
        XCTAssertTrue(AssetBook(nil).isEmpty)
    }

    func testSingleSheetWithASingleSection() {
        let book = AssetBook(assets: [asset("Home", 450_000, sheet: "Real estate", section: "Primary")])

        XCTAssertEqual(book.sheets.count, 1)
        XCTAssertEqual(book.sheets[0].sections.count, 1)
        XCTAssertEqual(book.sheets[0].rowCount, 1)
        XCTAssertEqual(book.sheets[0].total, 450_000, accuracy: 0.001)
        XCTAssertFalse(book.isEmpty)
    }

    /// Two assets may carry the same name in one section — Kubera does not stop
    /// you having two "Savings" rows — so both survive and stay addressable.
    func testAssetsSharingANameKeepBothRows() {
        let book = AssetBook(assets: [
            asset("Savings", 26_000, sheet: "Cash", section: "Reserve"),
            asset("Savings", 14_000, sheet: "Cash", section: "Reserve"),
        ])
        let rows = book.sheets[0].sections[0].rows

        XCTAssertEqual(rows.map(\.name), ["Savings", "Savings"])
        XCTAssertEqual(rows.map(\.value), [26_000, 14_000])
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertEqual(book.sheets[0].sections[0].total, 40_000, accuracy: 0.001)
    }

    /// Identical in every field, which is the only case where the id cannot be
    /// derived from the asset at all.
    func testIdenticalAssetsStillGetDistinctRowIDs() {
        let duplicate = asset("Savings", 26_000, sheet: "Cash", section: "Reserve")
        let rows = AssetBook(assets: [duplicate, duplicate]).sheets[0].sections[0].rows

        XCTAssertEqual(rows.count, 2)
        XCTAssertNotEqual(rows[0].id, rows[1].id)
    }

    func testSectionsSharingANameAcrossSheetsGetDistinctIDs() {
        let book = AssetBook(assets: [
            asset("A", 100, sheet: "Investments", section: "Taxable"),
            asset("B", 50, sheet: "Family", section: "Taxable"),
        ])
        let ids = book.sheets.flatMap { $0.sections.map(\.id) }

        XCTAssertEqual(Set(ids).count, 2)
    }

    // MARK: - Zero and negative values

    func testZeroValuedAssetsAreKept() {
        let book = AssetBook(assets: [
            asset("Closed account", 0, sheet: "Cash", section: "Everyday"),
            asset("Checking", 48_000, sheet: "Cash", section: "Everyday"),
        ])

        XCTAssertEqual(book.sheets[0].sections[0].rows.map(\.name), ["Checking", "Closed account"])
        XCTAssertEqual(book.total, 48_000, accuracy: 0.001)
    }

    func testNegativeAssetsAreKeptAndCountAgainstTheirTotals() {
        let book = AssetBook(assets: [
            asset("Overdrawn", -2_000, sheet: "Cash", section: "Everyday"),
            asset("Checking", 10_000, sheet: "Cash", section: "Everyday"),
        ])
        let section = book.sheets[0].sections[0]

        XCTAssertEqual(section.rows.map(\.name), ["Checking", "Overdrawn"])
        XCTAssertEqual(section.total, 8_000, accuracy: 0.001)
        XCTAssertEqual(book.total, 8_000, accuracy: 0.001)
    }

    /// A section that nets out negative sorts last rather than being hidden: it
    /// is part of the sheet total either way, and a row missing from a table
    /// that prints its own sum is unreadable.
    func testASectionWithANegativeTotalStillAppears() {
        let book = AssetBook(assets: [
            asset("Loan against policy", -5_000, sheet: "Misc", section: "Borrowed"),
            asset("Watch", 34_000, sheet: "Misc", section: "Watches"),
        ])

        XCTAssertEqual(book.sheets[0].sections.map(\.name), ["Watches", "Borrowed"])
        XCTAssertEqual(book.sheets[0].total, 29_000, accuracy: 0.001)
    }

    // MARK: - Lookups and view helpers

    func testSheetLookupFallsBackToTheLargestSheet() {
        let book = AssetBook(detail(sample))

        XCTAssertEqual(book.sheet(id: nil)?.name, "Investments")
        XCTAssertEqual(book.sheet(id: "Retired sheet")?.name, "Investments")
        XCTAssertEqual(book.sheet(id: "Cash")?.name, "Cash")
    }

    func testSheetTotalsExposedForTheSwitchersSharedUnit() {
        XCTAssertEqual(AssetBook(detail(sample)).sheetTotals, [860_000, 74_000])
    }

    /// The figures a sheet's table prints — every row, every section footer, and
    /// the sheet's own total — so one `Format.unit` can cover the column.
    func testSheetAmountsCoverRowsAndTotals() {
        let sheet = AssetBook(detail(sample)).sheets[0]

        XCTAssertEqual(sheet.rowCount, 3)
        XCTAssertEqual(sheet.amounts.count, sheet.rowCount + sheet.sections.count + 1)
        XCTAssertEqual(sheet.amounts.max(), 860_000, "the sheet's own total is the widest figure in its table")
        XCTAssertEqual(sheet.amounts.min(), 190_000)
    }
}

// MARK: - The demo book

/// `DemoData` is what a new user sees before connecting anything, and it is what
/// every `AssetDetailView` preview renders. A demo book of ten rows in
/// one-row sections made the detail screen look broken rather than empty — the
/// tables had nothing to total and the disclosure control had nothing to hide —
/// so its depth is asserted here rather than left to whoever edits the fixture
/// next.
extension AssetBookTests {
    private var demoBook: AssetBook { AssetBook(DemoData.detail) }

    func testDemoBookTotalsTheDemoAssetSide() throws {
        let book = demoBook

        XCTAssertEqual(book.total, try XCTUnwrap(DemoData.detail.assetTotal), accuracy: 0.01)
        XCTAssertEqual(book.total, DemoData.snapshot.assetTotal, accuracy: 0.01)
    }

    /// The sheet totals are load-bearing beyond this screen: `SankeyTests` pins
    /// the branch count and their sum, and the composition breakdown draws its
    /// bars from the same figures. Sections and rows underneath them may be
    /// reshaped freely; these six numbers may not move on their own.
    func testDemoSheetTotalsAreThePinnedOnes() {
        let totals = demoBook.sheets.map { ($0.name, $0.total) }

        XCTAssertEqual(totals.map(\.0), [
            "Investments", "Real estate", "Crypto", "Banks", "Vehicles", "Collectibles",
        ])
        XCTAssertEqual(totals.map(\.1), [860_000, 450_000, 130_000, 74_000, 62_000, 34_000])
    }

    func testDemoBookHasEnoughDepthToExerciseTheScreen() {
        let book = demoBook
        let sections = book.sheets.flatMap(\.sections)

        XCTAssertEqual(book.sheets.count, 6, "the switcher needs several tabs to scroll")
        XCTAssertEqual(sections.count, 13, "each sheet needs more than one table")
        XCTAssertEqual(book.sheets.reduce(0) { $0 + $1.rowCount }, 25)
        XCTAssertTrue(sections.allSatisfy { !$0.rows.isEmpty }, "a section with no rows would total nothing")
        XCTAssertTrue(
            book.sheets.allSatisfy { $0.rowCount > 1 },
            "a sheet of single-row sections is a footer restating the row above it"
        )
        XCTAssertTrue(
            book.sheets.contains { sheet in sheet.sections.contains { $0.rows.count > 2 } },
            "at least one table should be long enough to show the hairlines doing their job"
        )
    }

    /// The two rows that only exist to put an edge case on screen. Both are
    /// decisions this file records — unfiled money is parked rather than dropped,
    /// and a closed account stays in the table at zero.
    func testDemoBookCarriesAParkedRowAndAZeroRow() {
        let book = demoBook
        let sections = book.sheets.flatMap(\.sections)
        let rows = sections.flatMap(\.rows)

        XCTAssertTrue(
            sections.contains { $0.name == OverviewModules.unsortedGroupName },
            "keep an unsectioned asset so the parking path is something the demo shows"
        )
        XCTAssertTrue(rows.contains { $0.value == 0 }, "keep a zero-valued row for the same reason")
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty })
    }

    /// The Overview's top-holdings card and this screen are two views of one
    /// portfolio. A holding named in the card with no matching row in the tables
    /// reads as a bug in whichever the reader looked at second.
    func testDemoTopHoldingsAppearInTheBookAtTheSameValue() {
        let rows = demoBook.sheets.flatMap { $0.sections.flatMap(\.rows) }

        for holding in DemoData.snapshot.topHoldings {
            guard let row = rows.first(where: { $0.name == holding.name }) else {
                XCTFail("\(holding.name) is a top holding with no row in the book")
                continue
            }
            XCTAssertEqual(row.value, holding.value, accuracy: 0.01, holding.name)
        }
    }
}


// MARK: - Deep-link lookups

/// The Overview's composition rows are the entry point into this screen. A row
/// grouped by sheet carries a name that is already a `Sheet.id`; a row grouped
/// by section carries a name that may belong to several sheets, or to none.
/// Resolving that here rather than in the view keeps the ambiguity rule
/// testable, and keeps the screen's API down to one optional id.
extension AssetBookTests {
    func testASectionNameHeldByOneSheetResolvesToThatSheet() {
        let book = AssetBook(detail(sample))

        XCTAssertEqual(book.sheetID(forSection: "Taxable"), "Investments")
        XCTAssertEqual(book.sheetID(forSection: "Reserve"), "Cash")
    }

    /// The rule the resolver exists for: a name two sheets share names no single
    /// destination, so the caller opens the default view rather than being sent
    /// to whichever sheet happened to be larger.
    func testASectionNameSharedBySheetsResolvesToNothing() {
        let book = AssetBook(assets: [
            asset("A", 100, sheet: "Investments", section: "Misc"),
            asset("B", 50, sheet: "Collectibles", section: "Misc"),
        ])

        XCTAssertNil(book.sheetID(forSection: "Misc"))
    }

    /// The same rule reaching the case it was written for: unfiled rows can sit
    /// under every sheet at once, so "Unsorted" usually points nowhere.
    func testUnsortedResolvesOnlyWhenOneSheetHasUnfiledRows() {
        let single = AssetBook(assets: [
            asset("Filed", 100, sheet: "Investments", section: "Taxable"),
            asset("Unfiled", 50, sheet: "Vehicles", section: nil),
        ])
        XCTAssertEqual(single.sheetID(forSection: OverviewModules.unsortedGroupName), "Vehicles")

        let several = AssetBook(assets: [
            asset("Unfiled here", 100, sheet: "Investments", section: nil),
            asset("Unfiled there", 50, sheet: "Vehicles", section: nil),
        ])
        XCTAssertNil(several.sheetID(forSection: OverviewModules.unsortedGroupName))
    }

    func testAnUnknownOrBlankSectionNameResolvesToNothing() {
        let book = AssetBook(detail(sample))

        XCTAssertNil(book.sheetID(forSection: "Retired section"))
        XCTAssertNil(book.sheetID(forSection: ""))
        XCTAssertNil(book.sheetID(forSection: "   "))
        XCTAssertNil(AssetBook(assets: []).sheetID(forSection: "Taxable"))
    }

    /// Trimmed the same way the labels themselves are, so a name that arrives
    /// with the whitespace Kubera's markdown left on it still resolves.
    func testSectionNamesAreTrimmedBeforeResolving() {
        XCTAssertEqual(AssetBook(detail(sample)).sheetID(forSection: "  Taxable \n"), "Investments")
    }

    /// The two halves of a deep link, together: whatever the resolver answers —
    /// including nil — `sheet(id:)` turns into a sheet the screen can open.
    func testEveryResolverAnswerOpensASheet() {
        let book = AssetBook(detail(sample))

        for name in ["Taxable", "Reserve", "Retired section", ""] {
            XCTAssertNotNil(
                book.sheet(id: book.sheetID(forSection: name)),
                "\(name) left the screen with no sheet to open"
            )
        }
    }

    func testTheDemoBooksSectionsResolveWhereTheyAreUnique() {
        let book = AssetBook(DemoData.detail)

        XCTAssertEqual(book.sheetID(forSection: "Taxable"), "Investments")
        XCTAssertEqual(book.sheetID(forSection: "Wallets"), "Crypto")
        XCTAssertEqual(book.sheetID(forSection: "Watches"), "Collectibles")
    }
}

// MARK: - The Overview's deep link

/// The composition card hands `AssetDetailView` a row name and expects a sheet
/// back. That contract spans two modules — `OverviewModules.composition` decides
/// what a row is called, `AssetBook` decides what a sheet is called — and
/// neither file can hold the test on its own. If either changes how it trims or
/// labels a group, the link starts opening the wrong sheet silently, so it is
/// pinned here.
extension AssetBookTests {
    /// Caps off, so every group is a real one rather than part of the fold.
    private func sheetGroups(_ assets: [PortfolioDetail.Asset]) -> [OverviewModules.CompositionGroup] {
        OverviewModules.composition(assets, by: .sheet, maximumGroups: .max, minimumPercent: 0)
    }

    func testEverySheetLevelRowNamesASheetInTheBook() {
        let assets = sample + [asset("Unfiled", 12_000), asset("Car", 62_000, sheet: "Vehicles")]
        let book = AssetBook(assets: assets)

        for group in sheetGroups(assets) {
            XCTAssertNotNil(
                book.sheets.first { $0.id == group.name },
                "the composition row \(group.name) opens a sheet this book does not have"
            )
        }
    }

    /// Including the parked row: both modules spell the unsorted group the same
    /// way, so an unfiled row deep-links like any other.
    func testTheUnsortedRowNamesTheUnsortedSheet() {
        let assets = [asset("Filed", 100, sheet: "Investments", section: "Taxable"), asset("Unfiled", 50)]
        let names = sheetGroups(assets).map(\.name)
        let book = AssetBook(assets: assets)

        XCTAssertTrue(names.contains(OverviewModules.unsortedGroupName))
        XCTAssertNotNil(book.sheets.first { $0.id == OverviewModules.unsortedGroupName })
    }

    /// The demo book through the card's real caps: every row the Overview draws
    /// either opens a sheet or is the "Other" fold, which deliberately opens the
    /// default view because it counts money from several sheets at once.
    func testEveryRowTheDemoOverviewDrawsResolvesOrIsTheFold() {
        let assets = DemoData.detail.assets
        let book = AssetBook(assets: assets)

        for group in OverviewModules.composition(assets, by: .sheet) {
            if group.name == OverviewModules.otherGroupName { continue }
            XCTAssertNotNil(book.sheets.first { $0.id == group.name }, group.name)
        }

        // Section level resolves where a name belongs to one sheet, and answers
        // nil where it does not; either way the screen opens on something.
        for group in OverviewModules.composition(assets, by: .section) {
            XCTAssertNotNil(book.sheet(id: book.sheetID(forSection: group.name)), group.name)
        }
    }
}

// MARK: - Where a composition row lands

/// `AssetBook.sheetID(forGroup:at:resolvingSectionsIn:)` is the whole of the
/// Overview's routing decision. It used to live in the view, where the test
/// bundle could not reach it; the rules it encodes are the kind that break
/// quietly — a row that opens the wrong sheet still opens *a* sheet — so they
/// are pinned here.
extension AssetBookTests {
    func testASheetRowNamesItsOwnSheet() {
        XCTAssertEqual(
            AssetBook.sheetID(forGroup: "Crypto", at: .sheet, resolvingSectionsIn: nil),
            "Crypto"
        )
    }

    /// The laziness the caller depends on: at sheet level no book is consulted,
    /// so the Overview need not build one on a screen that re-renders through
    /// every frame of a scrub.
    func testASheetRowResolvesWithoutABook() {
        for name in ["Investments", OverviewModules.unsortedGroupName] {
            XCTAssertEqual(
                AssetBook.sheetID(forGroup: name, at: .sheet, resolvingSectionsIn: nil),
                name,
                "\(name) needed a book it should not have needed"
            )
        }
    }

    func testASectionRowResolvesThroughTheBook() {
        let book = AssetBook(detail(sample))

        XCTAssertEqual(
            AssetBook.sheetID(forGroup: "Taxable", at: .section, resolvingSectionsIn: book),
            "Investments"
        )
        XCTAssertNil(AssetBook.sheetID(forGroup: "Taxable", at: .section, resolvingSectionsIn: nil))
    }

    /// The fold is nobody's sheet, at either level — including the case that
    /// makes it a rule rather than a spelling: a portfolio that really does have
    /// a sheet named "Other", whose row has still absorbed the rest of the list.
    func testTheOtherFoldNeverResolves() {
        let book = AssetBook(assets: [
            asset("A", 100, sheet: OverviewModules.otherGroupName, section: "Bits"),
            asset("B", 900, sheet: "Investments", section: "Taxable"),
        ])

        XCTAssertNotNil(book.sheets.first { $0.id == OverviewModules.otherGroupName })
        for level in OverviewModules.CompositionLevel.allCases {
            XCTAssertNil(
                AssetBook.sheetID(forGroup: OverviewModules.otherGroupName, at: level, resolvingSectionsIn: book),
                "the fold resolved at \(level)"
            )
        }
    }

    func testAmbiguousAndBlankGroupsResolveToNothing() {
        let book = AssetBook(assets: [
            asset("A", 100, sheet: "Investments", section: "Misc"),
            asset("B", 50, sheet: "Collectibles", section: "Misc"),
        ])

        XCTAssertNil(AssetBook.sheetID(forGroup: "Misc", at: .section, resolvingSectionsIn: book))
        for level in OverviewModules.CompositionLevel.allCases {
            XCTAssertNil(AssetBook.sheetID(forGroup: "", at: level, resolvingSectionsIn: book))
            XCTAssertNil(AssetBook.sheetID(forGroup: "   ", at: level, resolvingSectionsIn: book))
        }
    }

    /// Whatever the rule answers, the screen can open it — nil included.
    func testEveryAnswerOpensASheet() {
        let book = AssetBook(detail(sample))

        for level in OverviewModules.CompositionLevel.allCases {
            for group in OverviewModules.composition(sample, by: level) {
                let resolved = AssetBook.sheetID(forGroup: group.name, at: level, resolvingSectionsIn: book)
                XCTAssertNotNil(book.sheet(id: resolved), "\(group.name) at \(level)")
            }
        }
    }
}

// MARK: - What a reset lands on

/// Re-tapping the Assets tab puts the screen back the way it was first seen, and
/// it does that by *clearing* the sheet selection rather than naming a sheet.
/// That only produces the leading tab of the switcher because nil and "the first
/// sheet" are the same answer here — which is this book's promise, not the
/// screen's, so it is pinned here.
extension AssetBookTests {
    func testClearingTheSelectionLandsOnTheLeadingSheet() {
        let book = AssetBook(detail(sample))

        XCTAssertEqual(book.sheet(id: nil)?.id, book.sheets.first?.id)
        XCTAssertEqual(book.sheet(id: nil)?.name, "Investments", "the leftmost tab is the largest sheet")
    }

    /// The same on the fixture the previews and the demo run use, where the
    /// switcher has six tabs to walk back to the start of.
    func testTheDemoBooksResetLandsOnItsFirstTab() {
        let book = AssetBook(DemoData.detail)

        XCTAssertEqual(book.sheet(id: nil)?.name, book.sheets.first?.name)
        XCTAssertEqual(book.sheet(id: nil)?.name, "Investments")
    }

    /// A reset on an empty book has nothing to land on and must not invent
    /// something to show.
    func testAResetOnAnEmptyBookStillHasNoSheet() {
        XCTAssertNil(AssetBook(assets: []).sheet(id: nil))
    }
}
