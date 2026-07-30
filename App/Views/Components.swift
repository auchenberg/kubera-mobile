import SwiftUI

/// The radius of every `Card`, and the container radius nested controls resolve
/// their own corners against. File-scope rather than a static on `Card` because
/// `Card` is generic, so a static would need its type argument spelled out at
/// every use.
private let cardCornerRadius: CGFloat = 16

/// Rounded container used for every grouped block in the app.
struct Card<Content: View>: View {
    var padding: EdgeInsets = .card
    @ViewBuilder var content: () -> Content

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: borderWidth))
            // Applied after the padding on purpose: concentric resolution
            // measures a child's distance to the container's edges, so the
            // container must be the *padded* frame for `16 - padding` to be the
            // radius a nested control resolves.
            .modifier(CardContainerShape())
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    /// A hairline disappears for the users who turn Increase Contrast on, which
    /// is the opposite of what they asked for.
    private var borderWidth: CGFloat {
        contrast == .increased ? 1 : 1 / displayScale
    }
}

/// Declares the shape a `Card`'s descendants resolve concentric corners against.
///
/// Deliberately not applied below iOS 26: there is no concentric resolution
/// before then, so the pre-26 `containerShape` overload would only set a value
/// nothing reads — and asking for it in both branches makes the call ambiguous
/// between the `InsettableShape` and `RoundedRectangularShape` overloads.
private struct CardContainerShape: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.containerShape(.rect(cornerRadius: cardCornerRadius))
        } else {
            content
        }
    }
}

extension View {
    /// Clips to a corner that shares a centre with the enclosing container's —
    /// `Card` declares that container, everything else falls back to a fixed
    /// radius.
    ///
    /// `minimum` is not optional in practice: when a corner sits too far from
    /// the container's corresponding edge its resolved radius falls back to 0,
    /// and a control inset inside a tall card is exactly that case. `isUniform`
    /// then makes every corner adopt the largest resolved radius so the four do
    /// not disagree.
    func concentricCorners(fallbackRadius: CGFloat, minimum: CGFloat = 8) -> some View {
        modifier(ConcentricCornersModifier(fallbackRadius: fallbackRadius, minimum: minimum))
    }
}

private struct ConcentricCornersModifier: ViewModifier {
    let fallbackRadius: CGFloat
    let minimum: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // `.fixed(_:)` rather than the literal `8`: `Edge.Corner.Style` is
            // only expressible by a *literal*, so a CGFloat parameter needs it.
            content.clipShape(.rect(corners: .concentric(minimum: .fixed(minimum)), isUniform: true))
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous))
        }
    }
}

extension EdgeInsets {
    static let card = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    /// For cards that host a list of rows, where each row pads itself.
    static let cardRows = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
}

/// The heading every tab opens with.
///
/// Deliberately a view inside the scroll content rather than a
/// `.navigationTitle`. A large title reserves its own bar above the content and
/// sits it much lower down the screen, which made the Overview — whose greeting
/// is drawn this way — start visibly higher than the other two tabs. Pair this
/// with `.toolbar(.hidden, for: .navigationBar)` so nothing reserves that space.
///
/// The type matches the Overview greeting exactly: change one and change both,
/// or the tabs drift apart again.
struct ScreenHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    @ViewBuilder private let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(.title, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                trailing()
            }

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .lineSpacing(4)
                    .foregroundStyle(Theme.dim)
                    // Explanatory copy takes the height it needs; without this
                    // it renders as one truncated line.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionTitle: View {
    private let title: String

    // `.textCase(.uppercase)` rather than `String.uppercased()` so the casing is
    // the presentation layer's and follows the locale's rules.
    @ScaledMetric(relativeTo: .caption) private var topPadding: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var bottomPadding: CGFloat = 8

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .kerning(1)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}

/// Hairline used to separate rows inside a card.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: contrast == .increased ? 1 : 1 / displayScale)
    }
}

struct ActionButton: View {
    enum Kind {
        case primary
        case destructive
    }

    let title: String
    var kind: Kind = .primary
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 50
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            ZStack {
                // Keeps the button from resizing when the spinner swaps in.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(foreground)
                }
            }
            .font(.body.weight(.semibold))
            // Set on the label rather than left to the button style so the
            // spinner's tint and the title always agree, and so a destructive
            // button keeps white-on-red under either style.
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .modifier(ActionButtonStyling(
            background: background,
            foreground: foreground,
            allowGlass: !reduceTransparency
        ))
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.6 : 1)
    }

    private var background: Color {
        kind == .primary ? Theme.accent : Theme.negative
    }

    private var foreground: Color {
        kind == .primary ? Theme.background : .white
    }
}

/// A small action sized to its own label.
///
/// `ActionButton` is full-width and heavily filled, which reads as "this is the
/// point of the screen" — right for the connect flow, wrong for a utility action
/// sitting beside content. Two of those stacked on the Widgets tab outweighed the
/// widget previews they exist to serve, and in light mode a pair of near-black
/// slabs was the first thing the eye landed on.
struct CompactButton: View {
    enum Kind {
        /// Filled. At most one per screen.
        case prominent
        /// Outlined, for anything the screen offers but does not lead with.
        case secondary
    }

    let title: String
    var systemImage: String?
    var kind: Kind = .secondary
    var isLoading = false
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 36

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.footnote.weight(.semibold))
                }
                Text(title)
                    // The label wraps at accessibility sizes, and the capsule
                    // has to grow with it — without this the second line
                    // rendered outside the fill.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            // Sized to the label, except at accessibility sizes where a
            // two-word label needs the whole width to stay on one line.
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
            .contentShape(.capsule)
        }
        .modifier(CompactButtonStyling(
            kind: kind,
            borderWidth: 1 / displayScale,
            allowGlass: !reduceTransparency
        ))
        .disabled(isLoading)
    }

    private var foreground: Color {
        kind == .prominent ? Theme.background : Theme.text
    }
}

private struct CompactButtonStyling: ViewModifier {
    let kind: CompactButton.Kind
    let borderWidth: CGFloat
    let allowGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), allowGlass {
            switch kind {
            case .prominent:
                content.tint(Theme.accent).buttonStyle(.glassProminent)
            case .secondary:
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(FlatCompactStyle(kind: kind, borderWidth: borderWidth))
        }
    }
}

private struct FlatCompactStyle: ButtonStyle {
    let kind: CompactButton.Kind
    let borderWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(kind == .prominent ? Theme.accent : Theme.card, in: .capsule)
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Theme.border, lineWidth: borderWidth)
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// `.glassProminent` on iOS 26 — which also supplies the press feedback the flat
/// style has to fake — and the flat fill below it, or whenever Reduce
/// Transparency is on, where a known-opaque fill is the whole point.
private struct ActionButtonStyling: ViewModifier {
    let background: Color
    let foreground: Color
    let allowGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), allowGlass {
            // The prominent glass fill comes from the tint, so this is what
            // carries "primary" versus "destructive".
            content
                .tint(background)
                .buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(FilledButtonStyle(background: background, foreground: foreground))
        }
    }
}

private struct FilledButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background)
            .concentricCorners(fallbackRadius: 12)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
