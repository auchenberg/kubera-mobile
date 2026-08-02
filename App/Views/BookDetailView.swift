import SwiftUI
import UIKit

/// One side of the portfolio, drilled down: Kubera's own sheet switcher over its
/// section tables, at phone width.
///
/// Assets and Debts are the same screen. Kubera files what you owe exactly like
/// what you own — sheets holding sections holding rows — so `side` is the entire
/// difference between the two tabs: which rows arrive, what the heading falls
/// back to, which tab a reset and a request name, and what the empty state says.
///
/// The desktop app puts every sheet in one row of tabs and every section in a
/// collapsible table with a column header and a footer total. That structure
/// survives the narrower screen intact — the tab row scrolls sideways because
/// the sheet count is the portfolio's business, and each table loses the cost
/// and IRR columns, which our MCP payload does not carry. Name and value is
/// what the data says, so name and value is what a row prints.
///
/// All grouping, ranking and totalling is `PortfolioBook`'s; this file is layout,
/// selection and disclosure state only.
struct BookDetailView: View {
    private let side: PortfolioSide
    private let book: PortfolioBook
    private let currency: String
    private let masked: Bool
    private let compactNumbers: Bool
    /// The latest request to show a book, from `AppStore`. Requests naming the
    /// other side are ignored, so both screens can watch one channel.
    ///
    /// It has two jobs, which is why it is both read and watched. Read once at
    /// construction, it seeds the switcher — a request that arrives before this
    /// tab has ever been shown *is* the screen's first frame rather than a
    /// change to it, so the right sheet is up before anything is drawn. Watched
    /// afterwards, it moves the switcher: tapping "Real estate" on the Overview
    /// while this tab already sits on Crypto has to land on Real estate, and a
    /// value seeded once could never do that.
    ///
    /// A request carrying no sheet leaves the selection alone, because "show me
    /// the assets" is not "show me a particular book".
    private let request: BookRequest?

    /// A sheet this book does not have — one renamed or emptied since the
    /// request was made — falls back to the largest sheet through
    /// `PortfolioBook.sheet(id:)` rather than showing nothing.
    init(
        side: PortfolioSide,
        book: PortfolioBook,
        currency: String,
        masked: Bool,
        compactNumbers: Bool = true,
        request: BookRequest? = nil
    ) {
        self.side = side
        self.book = book
        self.currency = currency
        self.masked = masked
        self.compactNumbers = compactNumbers
        self.request = request
        // Only a request for this side may seed it; the other screen's request
        // is not this screen's business, even on the first frame.
        _selectedSheetID = State(initialValue: request?.side == side ? request?.sheetID : nil)
    }

    /// The form the Overview wires: a nil detail is the fetch not having landed,
    /// which builds the empty book and renders the empty state rather than
    /// making the caller choose between two screens.
    init(
        side: PortfolioSide,
        detail: PortfolioDetail?,
        currency: String,
        masked: Bool,
        compactNumbers: Bool = true,
        request: BookRequest? = nil
    ) {
        self.init(
            side: side,
            book: PortfolioBook(side, in: detail),
            currency: currency,
            masked: masked,
            compactNumbers: compactNumbers,
            request: request
        )
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sheet on screen: seeded and re-seeded from `request`, and owned by
    /// the switcher in between. Nil means nobody has chosen, which
    /// `PortfolioBook.sheet(id:)` reads as the largest sheet — as it does for an id
    /// a refetch has renamed away.
    @State private var selectedSheetID: String?
    /// Collapsed rather than expanded ids: sections open by default, so the
    /// empty set is the default state and a new section arrives open.
    @State private var collapsed: Set<String> = []
    /// Held in `@State` so the generator survives re-renders with its
    /// `prepare()` still in effect.
    @State private var selectionHaptics = UISelectionFeedbackGenerator()

    /// The tab row bleeds to both screen edges, so a tab scrolling off does not
    /// stop at an inset and look clipped.
    private static let screenInset: CGFloat = 20

    private var selectedSheet: PortfolioBook.Sheet? { book.sheet(id: selectedSheetID) }

    /// The screen's heading: the sheet the switcher is on, so it says where you
    /// are rather than only what it is.
    ///
    /// The side's own name is the fallback for a book with no sheets, and is
    /// also the tab's name, so the heading is never blank and never a name the
    /// reader cannot see anything behind.
    ///
    /// This reads `selectedSheet`, which is seeded in `init` — a deep-linked
    /// open therefore carries the right name in its first frame. Moving that
    /// seed to `onAppear` would put "Assets" on screen for a frame before the
    /// real name replaced it.
    private var title: String { selectedSheet?.name ?? side.title }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same padding as the Widgets and Settings headers, so the
                // four tabs open at one height.
                //
                // Unlike those two it does not print the tab's own name. A tab
                // root usually is its tab, but this one is a switcher over five
                // or six books of figures, and "which one am I looking at" is
                // the question the top of the screen should answer — the tab bar
                // below still names the side. The cost is that the name also
                // appears in the selected tab just under it; the heading answers
                // where you are, the row answers where else you can go.
                ScreenHeader(title)
                    .tabTopAnchor()
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    // Crossfades instead of cutting when a request or a tap
                    // changes it. Both animate, so this costs nothing on the
                    // first frame, where there is no animation to join.
                    .contentTransition(.opacity)

                if let sheet = selectedSheet {
                    sheetSwitcher
                        .padding(.horizontal, -Self.screenInset)
                        .padding(.bottom, 4)
                    sections(of: sheet)
                } else {
                    emptyState
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Self.screenInset)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .softTopScrollEdge()
        // No navigation bar: `ScreenHeader` is this screen's heading, matching
        // the Widgets and Settings tabs, and there is no back button to keep —
        // the Overview no longer pushes this screen, it switches to its tab.
        .toolbar(.hidden, for: .navigationBar)
        .scrollsToTopOnTabReset(of: side.tab)
        // This screen's own share of a reset: the state above, put back the way
        // it is on a fresh build. Declared here rather than known anywhere
        // central — the scroll above is a separate participant, and neither
        // knows about the other.
        //
        // Clearing the selection rather than naming the first sheet is what
        // makes "as first seen" literally true: nil is "nobody has chosen",
        // which `PortfolioBook` reads as the largest sheet, exactly as it does when
        // the screen is built. Which sections were folded is transient too, so
        // they come back open.
        //
        // It composes with `request` rather than fighting it: a later deep link
        // carries a new serial, so it still wins after a reset, and the request
        // already spent does not re-apply itself.
        .onTabReset(of: side.tab) {
            selectedSheetID = nil
            collapsed = []
        }
        .onChange(of: request) { _, new in
            // Only an explicit sheet moves the switcher. A bare "show me the
            // assets" — the ASSETS card, `kubera://assets` — leaves the reader
            // on whatever they were last looking at.
            guard let new, new.side == side, let sheetID = new.sheetID else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selectedSheetID = sheetID
            }
        }
        .task { selectionHaptics.prepare() }
    }

    // MARK: - Sheet switcher

    /// The sheets as a scrolling row of tabs, each its name over its total.
    ///
    /// Scrolling sideways rather than wrapping or folding into a menu: how many
    /// sheets there are is the portfolio's business, the desktop app shows them
    /// in one row, and a menu would hide the totals that make the row worth
    /// reading. The selected tab is scrolled into view, so a tab tapped at the
    /// edge finishes the gesture fully visible.
    private var sheetSwitcher: some View {
        // One unit across the row: these totals sit side by side and are read
        // against each other, and tabs are too narrow for an exact figure.
        let unit = Format.unit(spanning: book.sheetTotals, compact: true)

        return ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(book.sheets) { sheet in
                        sheetTab(sheet, unit: unit)
                    }
                }
                .padding(.horizontal, Self.screenInset)
            }
            // Watches the *resolved* sheet, not the raw selection: a reset
            // clears the selection to nil, and it is the sheet that stands in
            // for nil — the leading one — that the row has to travel back to.
            .onChange(of: selectedSheet?.id) { _, new in
                guard let new else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    scroller.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func sheetTab(_ sheet: PortfolioBook.Sheet, unit: Format.Unit) -> some View {
        let active = sheet.id == selectedSheet?.id

        return Button {
            selectionHaptics.selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selectedSheetID = sheet.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(active ? Theme.text : Theme.dim)
                Text(Format.money(sheet.total, currency: currency, masked: masked, unit: unit))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(active ? Theme.text.opacity(0.85) : Theme.dim)
                    .contentTransition(.numericText(value: sheet.total))
                // An underline rather than a filled pill: a two-line tab set in
                // solid `Theme.text` is a slab heavy enough to outweigh the table
                // it is a control for. Colour is not the only carrier — the
                // selected tab is also the only one at full strength.
                Rectangle()
                    .fill(active ? Theme.text : Color.clear)
                    .frame(height: 2)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sheet.name)
        .accessibilityValue(Format.money(sheet.total, currency: currency, masked: masked, compact: false))
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Section tables

    @ViewBuilder
    private func sections(of sheet: PortfolioBook.Sheet) -> some View {
        // One unit for the whole sheet, rows and totals alike: a footer in a
        // different notation from the rows above it cannot be checked against
        // them. At accessibility sizes the figure compacts whatever the
        // preference says — the row has far less width for it there.
        let unit = Format.unit(
            spanning: sheet.amounts,
            compact: compactNumbers || typeSize.isAccessibilitySize
        )

        ForEach(sheet.sections) { section in
            SectionTitle(section.name)
            sectionCard(section, unit: unit)
        }
    }

    private func sectionCard(_ section: PortfolioBook.Section, unit: Format.Unit) -> some View {
        let expanded = !collapsed.contains(section.id)

        return Card(padding: .cardRows) {
            VStack(spacing: 0) {
                sectionHeader(section, expanded: expanded, unit: unit)

                if expanded {
                    VStack(spacing: 0) {
                        RowDivider()
                        if !typeSize.isAccessibilitySize {
                            columnHeader
                            RowDivider()
                        }
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider() }
                            assetRow(row, unit: unit)
                        }
                        RowDivider()
                        totalRow(section, unit: unit)
                    }
                    // Opacity alone: the card's own height change already carries
                    // the disclosure, and a slide inside a clipped card reads as
                    // the rows being pushed rather than revealed.
                    .transition(.opacity)
                }
            }
        }
    }

    /// The section's name and its disclosure control. The total moves up here
    /// while the section is collapsed — collapsing a section should hide its
    /// rows, not the figure they add up to.
    private func sectionHeader(
        _ section: PortfolioBook.Section,
        expanded: Bool,
        unit: Format.Unit
    ) -> some View {
        let name = Text(section.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
        let total = Text(Format.money(section.total, currency: currency, masked: masked, unit: unit))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)

        return Button {
            selectionHaptics.selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                if expanded {
                    collapsed.insert(section.id)
                } else {
                    collapsed.remove(section.id)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.dim)
                    .rotationEffect(.degrees(expanded ? 90 : 0))

                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        if !expanded { total }
                    }
                } else {
                    name
                    Spacer(minLength: 12)
                    if !expanded {
                        total.contentTransition(.numericText(value: section.total))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Spoken as one control: the name, whether it is open, and the count the
        // collapsed row does not show.
        .accessibilityLabel(section.name)
        .accessibilityValue(
            expanded
                ? "Expanded, \(section.rows.count) assets"
                : "Collapsed, \(section.rows.count) assets, "
                    + Format.money(section.total, currency: currency, masked: masked, compact: false)
        )
        .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand")
        .accessibilityAddTraits(.isHeader)
    }

    /// The table's column header, in the same small caps the desktop uses.
    /// Dropped at accessibility sizes, where the rows stack into labelled lines
    /// and a header would point at columns that no longer exist.
    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text(side.rowNoun)
            Spacer(minLength: 12)
            Text("Value")
        }
        .font(.caption2.weight(.semibold))
        .kerning(1)
        .textCase(.uppercase)
        .foregroundStyle(Theme.dim)
        .padding(.vertical, 8)
        // The rows below say the same thing in full words.
        .accessibilityHidden(true)
    }

    /// One asset. Name and value share a line until the type size stops them
    /// fitting, where the value drops below the name rather than either being
    /// truncated — an asset name cut mid-word and a figure scaled below the size
    /// the reader asked for are both worse than a taller row.
    ///
    /// A negative value stays `Theme.text`: green and red mean direction of
    /// change in this app, and a balance is not a change.
    private func assetRow(_ row: PortfolioBook.Row, unit: Format.Unit) -> some View {
        let name = Text(row.name)
            .font(.subheadline)
            .foregroundStyle(Theme.text)
        let value = Text(Format.money(row.value, currency: currency, masked: masked, unit: unit))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        return layout {
            name
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            value.contentTransition(.numericText(value: row.value))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        // One statement per asset — "Index funds, $430,000" — rather than two
        // fragments a swipe has to join up.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(Format.money(row.value, currency: currency, masked: masked, compact: false))
    }

    /// The footer row, carrying only the value: the desktop's cost and IRR
    /// totals have no source in our data.
    private func totalRow(_ section: PortfolioBook.Section, unit: Format.Unit) -> some View {
        let label = Text("Total")
            .font(.caption2.weight(.semibold))
            .kerning(1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.dim)
        let total = Text(Format.money(section.total, currency: currency, masked: masked, unit: unit))
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        return layout {
            label
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            total.contentTransition(.numericText(value: section.total))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.name) total")
        .accessibilityValue(Format.money(section.total, currency: currency, masked: masked, compact: false))
    }

    // MARK: - Empty

    /// Shown when the detail fetch has not landed, or landed with nothing on
    /// this side. It explains an absence rather than pretending to be a table.
    ///
    /// A portfolio with no debts is a real and happy state, unlike one with no
    /// assets, so the two sides do not read the same: one is waiting for data,
    /// the other may simply be finished.
    private var emptyState: some View {
        Card {
            Text(side == .assets
                ? "No assets to show yet. Sheets and sections fill in once Kubera's portfolio detail loads."
                : "No debts to show. Anything you owe in Kubera appears here, filed by sheet and section.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Assets") {
    NavigationStack {
        BookDetailView(side: .assets, detail: DemoData.detail, currency: "USD", masked: false)
    }
}

#Preview("Debts") {
    NavigationStack {
        BookDetailView(side: .debts, detail: DemoData.detail, currency: "USD", masked: false)
    }
}

#Preview("Assets — requested on Crypto") {
    NavigationStack {
        BookDetailView(
            side: .assets,
            detail: DemoData.detail,
            currency: "USD",
            masked: false,
            request: BookRequest(side: .assets, sheetID: "Crypto", serial: 1)
        )
    }
}

#Preview("Assets — masked") {
    NavigationStack {
        BookDetailView(side: .assets, detail: DemoData.detail, currency: "USD", masked: true)
    }
}

#Preview("Debts — dark") {
    NavigationStack {
        BookDetailView(side: .debts, detail: DemoData.detail, currency: "USD", masked: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("Assets — AX5") {
    NavigationStack {
        BookDetailView(side: .assets, detail: DemoData.detail, currency: "USD", masked: false)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Debts — empty") {
    NavigationStack {
        BookDetailView(side: .debts, detail: nil, currency: "USD", masked: false)
    }
}
#endif
