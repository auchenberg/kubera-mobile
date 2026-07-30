import SwiftUI

/// Liquid Glass for the controls layer, in one place.
///
/// Apple's rule is that glass sits *on top of* content and never becomes
/// content: nav bars, tab bars, floating controls, transient overlays. On the
/// Overview that means the range pill row and the scrub tooltip, and nothing
/// else — the data cards stay opaque `Theme.card`, because a monospaced figure
/// over a sampling backdrop stops being legible, which is the whole reason the
/// rule exists.
///
/// The deployment target is iOS 17 while the app builds against the iOS 26 SDK,
/// so every glass surface needs a fallback. Keeping the `#available` check in
/// one modifier means call sites read as design intent instead of version
/// plumbing, and there is a single place to delete when the target moves to 26.
extension View {
    /// A floating control surface: real Liquid Glass on iOS 26, a thin material
    /// with a hairline edge before that.
    ///
    /// `tint` is for legibility over busy content, never decoration — bare glass
    /// washes out over a chart's gradient fill, which is why the scrub tooltip
    /// passes `Theme.card` and the pill row, which floats over a flat card,
    /// passes nothing.
    func controlGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(ControlGlassModifier(shape: shape, tint: tint))
    }
}

private struct ControlGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                // Backgrounds stack back-to-front in reverse order of
                // application, so the material lands behind the tint and the
                // tint reads as a wash over it rather than under it.
                .background(tint.map { $0.opacity(0.5) } ?? .clear, in: shape)
                .background(.ultraThinMaterial, in: shape)
                // `.ultraThinMaterial` over a white card in light mode is very
                // nearly invisible; the hairline is what makes the control read
                // as a control at all before iOS 26.
                .overlay(shape.strokeBorder(Theme.border, lineWidth: 1 / displayScale))
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        guard let tint else { return .regular }
        // Low opacity on purpose: Apple's guidance is that a tint rescues
        // legibility or conveys meaning, and at full strength the surface reads
        // as a colored chip rather than as glass.
        return .regular.tint(tint.opacity(0.4))
    }
}
