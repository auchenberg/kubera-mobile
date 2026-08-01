import SwiftUI
import UIKit

/// The asset drill-down: Kubera's own sheet switcher over its section tables,
/// at phone width.
///
/// The desktop app puts every sheet in one row of tabs and every section in a
/// collapsible table with a column header and a footer total. That structure
/// survives the narrower screen intact — the tab row scrolls sideways because
/// the sheet count is the portfolio's business, and each table loses the cost
/// and IRR columns, which our MCP payload does not carry. Name and value is
/// what the data says, so name and value is what a row prints.
///
/// All grouping, ranking and totalling is `AssetBook`'s; this file is layout,
/// selection and disclosure state only.
struct AssetDetailView: View {
    /// Where the screen is being shown, which decides where its heading goes.
    ///
    /// Every tab root in this app hides the navigation bar and puts a
    /// `ScreenHeader` in its content, so the four headings sit at the same
    /// height; a pushed screen cannot do that, because hiding the bar would take
    /// the back button with it.
    enum Presentation {
        case pushed
        case tabRoot
    }

    private let book: AssetBook
    private let currency: String
    private let masked: Bool
    private let compactNumbers: Bool
    private let presentation: Presentation

    /// `initialSheetID` is where the switcher opens — the sheet a tap on the
    /// Overview asked for. It is a starting position, not a binding: once the
    /// reader touches a tab their choice wins, and an id this book does not
    /// have (a sheet renamed or emptied since the link was built) falls back to
    /// the largest sheet through `AssetBook.sheet(id:)` rather than showing
    /// nothing.
    ///
    /// SwiftUI seeds `@State` once per view identity, so a destination that is
    /// rebuilt in place with a different id keeps the sheet it already had.
    /// That is right for a pushed screen, where each link is its own identity,
    /// and worth knowing for anything that reuses one.
    init(
        book: AssetBook,
        currency: String,
        masked: Bool,
        compactNumbers: Bool = true,
        initialSheetID: String? = nil,
        presentation: Presentation = .pushed
    ) {
        self.book = book
        self.currency = currency
        self.masked = masked
        self.compactNumbers = compactNumbers
        self.presentation = presentation
        _selectedSheetID = State(initialValue: initialSheetID)
    }

    /// The form the Overview wires: a nil detail is the fetch not having landed,
    /// which builds the empty book and renders the empty state rather than
    /// making the caller choose between two screens.
    init(
        detail: PortfolioDetail?,
        currency: String,
        masked: Bool,
        compactNumbers: Bool = true,
        initialSheetID: String? = nil,
        presentation: Presentation = .pushed
    ) {
        self.init(
            book: AssetBook(detail),
            currency: currency,
            masked: masked,
            compactNumbers: compactNumbers,
            initialSheetID: initialSheetID,
            presentation: presentation
        )
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sheet on screen: seeded from `initialSheetID` and then owned by the
    /// switcher. Nil means nobody has chosen, which `AssetBook.sheet(id:)`
    /// reads as the largest sheet — as it does for an id a refetch has renamed
    /// away.
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

    private var selectedSheet: AssetBook.Sheet? { book.sheet(id: selectedSheetID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if presentation == .tabRoot {
                    // Same padding as the Widgets and Settings headers, so the
                    // four tabs open at one height.
                    ScreenHeader("Assets")
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }

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
        .modifier(AssetsChrome(presentation: presentation))
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
            .onChange(of: selectedSheetID) { _, new in
                guard let new else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    scroller.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func sheetTab(_ sheet: AssetBook.Sheet, unit: Format.Unit) -> some View {
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
    private func sections(of sheet: AssetBook.Sheet) -> some View {
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

    private func sectionCard(_ section: AssetBook.Section, unit: Format.Unit) -> some View {
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
        _ section: AssetBook.Section,
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
            Text("Asset")
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
    private func assetRow(_ row: AssetBook.Row, unit: Format.Unit) -> some View {
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
    private func totalRow(_ section: AssetBook.Section, unit: Format.Unit) -> some View {
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

    /// Shown when the detail fetch has not landed, or landed with no holdings.
    /// It explains an absence rather than pretending to be a table.
    private var emptyState: some View {
        Card {
            Text("No assets to show yet. Sheets and sections fill in once Kubera's portfolio detail loads.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The bar a pushed screen needs and a tab root must not have. Written as a
/// modifier rather than two `if`s in the body because `.toolbar(.hidden,)` and
/// `.navigationTitle` return different types.
private struct AssetsChrome: ViewModifier {
    let presentation: AssetDetailView.Presentation

    func body(content: Content) -> some View {
        switch presentation {
        case .pushed:
            // Inline, not large: the back button is the point of this bar, and a
            // large title would restate the sheet name already under it.
            content
                .navigationTitle("Assets")
                .navigationBarTitleDisplayMode(.inline)
        case .tabRoot:
            content.toolbar(.hidden, for: .navigationBar)
        }
    }
}

#if DEBUG
#Preview("Assets") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: false)
    }
}

#Preview("Assets — deep linked to Crypto") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: false, initialSheetID: "Crypto")
    }
}

#Preview("Assets — tab root") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: false, presentation: .tabRoot)
    }
}

#Preview("Assets — masked") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: true)
    }
}

#Preview("Assets — dark") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("Assets — AX5") {
    NavigationStack {
        AssetDetailView(detail: DemoData.detail, currency: "USD", masked: false)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Assets — empty") {
    NavigationStack {
        AssetDetailView(detail: nil, currency: "USD", masked: false)
    }
}
#endif
