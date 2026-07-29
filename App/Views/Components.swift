import SwiftUI

/// Rounded container used for every grouped block in the app.
struct Card<Content: View>: View {
    var padding: EdgeInsets = .card
    @ViewBuilder var content: () -> Content

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1 / displayScale)
            )
    }
}

extension EdgeInsets {
    static let card = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    /// For cards that host a list of rows, where each row pads itself.
    static let cardRows = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
}

struct SectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(1)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

/// Hairline used to separate rows inside a card.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1 / displayScale)
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

    var body: some View {
        Button(action: action) {
            ZStack {
                // Keeps the button from resizing when the spinner swaps in.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(foreground)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(FilledButtonStyle(background: background, foreground: foreground))
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

private struct FilledButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
