import Foundation

/// The sheets → sections → rows hierarchy behind the Assets and Debts screens:
/// the same shape Kubera's web app tabs through, grouped and ranked once so the
/// view is layout only.
///
/// One model for both sides. What you own and what you owe are filed the same
/// way in Kubera — sheets holding sections holding rows — so the maths here does
/// not know which it is grouping, and `PortfolioSide` is the only thing that
/// decides which rows arrive.
///
/// Foundation-only and pure, exactly like `OverviewChart`, `OverviewModules` and
/// `Sankey` — the test bundle compiles this without the app target.
///
/// Three rules the whole file follows:
///
/// - **Nothing is dropped.** Every asset lands in exactly one section of exactly
///   one sheet, so the sheet totals sum to the book's total and the book's total
///   is the portfolio's asset side. An asset with no sheet or no section is
///   parked under `OverviewModules.unsortedGroupName` at whichever level is
///   missing, the same trimming `OverviewModules.composition` does — it is real
///   money, just unfiled.
/// - **Zero and negative rows are kept.** Kubera shows them, and a table whose
///   rows do not sum to the total it prints is a table the reader cannot check.
///   Debt rows arrive as the positive magnitudes Kubera states them in, so a
///   debt book totals upwards and agrees with the DEBTS card; nothing here
///   negates a value.
///   This is the one place this file differs from `composition`, which drops
///   non-positive groups because a negative share of a pie is not a thing.
/// - **Ranking is by value, name breaking ties**, at all three levels, so the
///   same portfolio always renders in the same order.
struct PortfolioBook: Hashable, Sendable {
    // MARK: - Levels

    /// One asset as a table row: the name and the value, which is all our data
    /// carries. Kubera's desktop table also has cost and IRR columns; the MCP
    /// payload has neither, and a column of invented numbers would be worse than
    /// a missing column.
    struct Row: Hashable, Identifiable, Sendable {
        let name: String
        let value: Double
        /// Unique within the whole book. Composed rather than taken from the
        /// name because two assets in one section may share a name — Kubera does
        /// not stop you having two "Savings" rows, and `ForEach` needs to tell
        /// them apart.
        let id: String
    }

    /// A named group of rows inside a sheet, with the total the footer prints.
    struct Section: Hashable, Identifiable, Sendable {
        let name: String
        let rows: [Row]
        let total: Double
        /// Qualified by its sheet: section names repeat across sheets, and an id
        /// that collided would confuse a `ForEach` mid switch.
        let id: String
    }

    /// One tab of the switcher, and everything under it.
    struct Sheet: Hashable, Identifiable, Sendable {
        let name: String
        let sections: [Section]
        let total: Double

        var id: String { name }

        /// Every figure this sheet's table prints, for `Format.unit(spanning:)`.
        /// Rows and totals share one notation: a column that switches from
        /// "$130K" to "$74,000" partway down cannot be scanned, and the footer
        /// has to be readable against the rows it sums.
        var amounts: [Double] {
            sections.flatMap { section in [section.total] + section.rows.map(\.value) } + [total]
        }

        /// How many assets the sheet holds, for the count a collapsed section
        /// cannot show.
        var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }
    }

    // MARK: - The book

    /// Sheets, largest total first.
    let sheets: [Sheet]
    /// Every asset in the book, summed. This is the portfolio's asset side, so a
    /// screen may print it beside `PortfolioDetail.assetTotal` without the two
    /// disagreeing.
    let total: Double

    var isEmpty: Bool { sheets.isEmpty }

    /// The sheet totals the switcher prints, for a shared `Format.unit`.
    var sheetTotals: [Double] { sheets.map(\.total) }

    /// A sheet by id, falling back to the largest one. The switcher holds a name
    /// in state, and a refetch can rename or remove the sheet it is holding —
    /// this is what keeps that from emptying the screen.
    func sheet(id: String?) -> Sheet? {
        guard let id, let match = sheets.first(where: { $0.id == id }) else { return sheets.first }
        return match
    }

    /// The sheet holding a section of this name, for a caller that knows only
    /// the name — the Overview's composition rows group by section *across*
    /// sheets, so "Taxable" arrives without the sheet it belongs to.
    ///
    /// Nil unless exactly one sheet holds that name. Two sheets with a "Misc"
    /// section give the name no single destination, and picking the larger of
    /// them would send half the taps somewhere the reader did not ask for;
    /// answering nil lets the caller open the default view instead, which is
    /// honest about not knowing. `unsortedGroupName` is the case this rule
    /// exists for: it can appear under every sheet at once.
    func sheetID(forSection name: String) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let matches = sheets.filter { sheet in sheet.sections.contains { $0.name == wanted } }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// Where a composition row should land, by the level it was grouped at.
    ///
    /// The Overview hands over a row's name and nothing else, so this is the one
    /// place a name becomes a destination:
    ///
    /// - At sheet level the name *is* a `Sheet.id`, including the unsorted
    ///   group, which both modules spell the same way. No book is consulted: a
    ///   name this book no longer has degrades through `sheet(id:)` anyway.
    /// - At section level a name may belong to several sheets, so `book`
    ///   answers only when exactly one holds it. It is optional because the
    ///   caller need not pay for building a book at sheet level, where nothing
    ///   would be looked up in it.
    /// - The "Other" fold is nobody's sheet. Even where a sheet of that name
    ///   exists the row has absorbed the remainder of the list, so landing on it
    ///   would show a fraction of what was tapped.
    ///
    /// Every unknown comes back nil, which the screen reads as "open on the
    /// largest sheet".
    static func sheetID(
        forGroup name: String,
        at level: OverviewModules.CompositionLevel,
        resolvingSectionsIn book: PortfolioBook?
    ) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, wanted != OverviewModules.otherGroupName else { return nil }
        switch level {
        case .sheet: return wanted
        case .section: return book?.sheetID(forSection: wanted)
        }
    }

    // MARK: - Building

    /// Groups one side of a portfolio. A nil detail — the MCP fetch has not
    /// landed — builds the empty book, so a caller never has to decide between
    /// two screens.
    init(
        _ side: PortfolioSide,
        in detail: PortfolioDetail?,
        unsortedName: String = OverviewModules.unsortedGroupName
    ) {
        self.init(rows: detail?.rows(side) ?? [], unsortedName: unsortedName)
    }

    init(rows: [PortfolioDetail.Asset], unsortedName: String = OverviewModules.unsortedGroupName) {
        // Grouped through dictionaries and ranked afterwards rather than sorted
        // in place: the input order is Kubera's ranking of the whole portfolio,
        // which says nothing about the order inside a section.
        var grouped: [String: [String: [PortfolioDetail.Asset]]] = [:]
        for asset in rows {
            let sheet = Self.label(asset.sheet, fallback: unsortedName)
            let section = Self.label(asset.section, fallback: unsortedName)
            grouped[sheet, default: [:]][section, default: []].append(asset)
        }

        var sheets: [Sheet] = []
        for (sheetName, sectionsByName) in grouped {
            var sections: [Section] = []
            for (sectionName, rows) in sectionsByName {
                let sectionID = "\(sheetName)\(Self.idSeparator)\(sectionName)"
                let ranked = rows.sorted(by: Self.precedes)
                let ordered = ranked.enumerated().map { index, asset in
                    // The index rather than the name: two rows in one section may
                    // carry the same name, and after ranking the position is the
                    // only thing that separates them.
                    Row(
                        name: asset.name,
                        value: asset.value,
                        id: "\(sectionID)\(Self.idSeparator)\(index)"
                    )
                }
                sections.append(Section(
                    name: sectionName,
                    rows: ordered,
                    total: ordered.reduce(0) { $0 + $1.value },
                    id: sectionID
                ))
            }
            sections.sort(by: Self.precedes)
            sheets.append(Sheet(
                name: sheetName,
                sections: sections,
                total: sections.reduce(0) { $0 + $1.total }
            ))
        }
        sheets.sort(by: Self.precedes)

        self.sheets = sheets
        // Summed from the sheets rather than from `assets`, so the figure the
        // screen prints at the top is arithmetically the one its rows add up to.
        total = sheets.reduce(0) { $0 + $1.total }
    }

    // MARK: - Grouping rules

    /// Splits the id levels. A control character rather than a glyph: a sheet
    /// really can be called "Cars › Watches", and an id that collided with
    /// another sheet's would swap two sections under an animation.
    private static let idSeparator = "\u{001F}"

    /// One label, trimmed the way `OverviewModules.composition` trims it, with
    /// the unsorted name standing in for an absent or blank one.
    private static func label(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return fallback }
        return trimmed
    }

    /// Largest first, alphabetical where two are equal. Written once per level
    /// rather than shared through a protocol: three overloads of one rule read
    /// better here than a `Ranked` abstraction with three conformances.
    private static func precedes(_ left: PortfolioDetail.Asset, _ right: PortfolioDetail.Asset) -> Bool {
        left.value == right.value ? left.name < right.name : left.value > right.value
    }

    private static func precedes(_ left: Section, _ right: Section) -> Bool {
        left.total == right.total ? left.name < right.name : left.total > right.total
    }

    private static func precedes(_ left: Sheet, _ right: Sheet) -> Bool {
        left.total == right.total ? left.name < right.name : left.total > right.total
    }
}

// MARK: - Sides

/// Which side of the portfolio a book shows: what you own, or what you owe.
///
/// One value carries everything that differs between the two screens — which
/// rows a book is built from, what the screen is called, and which tab it lives
/// in. That is what let the Debts screen reuse the Assets one rather than fork
/// it: the difference between them is this enum and nothing else.
enum PortfolioSide: String, CaseIterable, Hashable, Sendable {
    case assets
    case debts

    /// The screen's heading fallback and its tab's label.
    var title: String {
        switch self {
        case .assets: "Assets"
        case .debts: "Debts"
        }
    }

    /// What one row is called, for the table's column header: a debt listed
    /// under "ASSET" reads as a filing error.
    var rowNoun: String {
        switch self {
        case .assets: "Asset"
        case .debts: "Debt"
        }
    }

    /// Where the screen lives. Spelled out rather than derived from `rawValue`
    /// so the compiler checks the pairing when either enum gains a case.
    var tab: AppTab {
        switch self {
        case .assets: .assets
        case .debts: .debts
        }
    }
}

extension PortfolioDetail {
    /// One side's rows. Debts are optional on the payload — a cache written
    /// before they were parsed has none — and an absent list is no rows here,
    /// because a screen with nothing to show is what "nobody looked" looks like.
    func rows(_ side: PortfolioSide) -> [Asset] {
        switch side {
        case .assets: assets
        case .debts: debts ?? []
        }
    }
}
