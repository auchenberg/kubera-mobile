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
    ///
    /// `isInteractive` is for surfaces the user taps; it adds the scale-and-
    /// highlight response that makes glass feel alive, and is dropped under
    /// Reduce Motion.
    func controlGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(ControlGlassModifier(shape: shape, tint: tint, isInteractive: isInteractive))
    }

    /// The soft top fade under a scroll view's leading edge.
    ///
    /// Written out rather than left to `.automatic` because iOS 27 flips the
    /// default to `.hard`: leaving it automatic means an OS upgrade silently
    /// changes how every screen's top edge looks.
    func softTopScrollEdge() -> some View {
        modifier(SoftTopScrollEdgeModifier())
    }
}

private struct ControlGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let isInteractive: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(glass, in: shape)
        } else {
            content
                // Backgrounds stack back-to-front in reverse order of
                // application, so the material lands behind the tint and the
                // tint reads as a wash over it rather than under it.
                .background(surfaceFill, in: shape)
                .background(surfaceMaterial, in: shape)
                // `.ultraThinMaterial` over a white card in light mode is very
                // nearly invisible; the hairline is what makes the control read
                // as a control at all before iOS 26.
                .overlay(shape.strokeBorder(Theme.border, lineWidth: borderWidth))
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint {
            // Low opacity on purpose: Apple's guidance is that a tint rescues
            // legibility or conveys meaning, and at full strength the surface
            // reads as a colored chip rather than as glass.
            glass = glass.tint(tint.opacity(0.4))
        }
        if isInteractive, !reduceMotion {
            glass = glass.interactive()
        }
        return glass
    }

    /// Reduce Transparency means "stop sampling what is behind this", so the
    /// fallback drops the material entirely rather than merely thickening it and
    /// promotes the tint to an opaque fill. `AnyShapeStyle` because `.background`
    /// needs one concrete type across both cases.
    private var surfaceFill: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(tint ?? Theme.card)
        }
        return AnyShapeStyle(tint.map { $0.opacity(0.5) } ?? Color.clear)
    }

    private var surfaceMaterial: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.ultraThinMaterial)
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1 : 1 / displayScale
    }
}

private struct SoftTopScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
