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
