import SwiftUI
import UIKit

/// App palette. Colors resolve per trait collection so they follow the system
/// appearance without every view reading `\.colorScheme`.
///
/// A few colors also resolve against `accessibilityContrast`, so Increase
/// Contrast is honoured without any call site changing. `Theme` is a namespace
/// of static properties and so cannot read `@Environment(\.colorSchemeContrast)`
/// itself; the `UIColor` dynamic provider is the only mechanism that keeps
/// `Theme.positive` a plain `Color` usable in `foregroundStyle`, `fill` and
/// `strokeBorder` alike. The cost is that these colors resolve through UIKit
/// traits rather than the SwiftUI environment, so a view that overrides
/// `\.colorSchemeContrast` in a preview will not affect them — only the real
/// system setting (and `.environment(\.colorScheme, _)`, which SwiftUI pushes
/// into the trait collection) does.
enum Theme {
    static let background = adaptive(light: 0xF4F5F7, dark: 0x0A0C12)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x151823)
    static let text = adaptive(light: 0x0B0E1A, dark: 0xF5F7FA)
    static let accent = adaptive(light: 0x0B0E1A, dark: 0xF5F7FA)
    static let widgetPreviewBg = adaptive(light: 0x0B0E1A, dark: 0x151823)

    // Contrast ratios below are measured against the surface the color actually
    // sits on — `card` (#FFFFFF light, #151823 dark) for figures inside a Card,
    // `background` where noted. WCAG wants ≥4.5:1 for body-size text and ≥3:1
    // for large text and graphical objects. Do not "brighten" the light-mode
    // green: #4ADE80 is ~1.8:1 on white, which is why light mode has its own
    // value. The numbers are recorded so the next change can be checked rather
    // than eyeballed.

    /// Secondary/explanatory copy. Carries most of the prose in Settings, so it
    /// is held above 4.5:1 in both appearances rather than treated as decoration.
    /// 4.83:1 light on card, 4.43:1 light on background, 5.73:1 dark on card.
    /// Increased contrast: 7.56:1 light, 8.68:1 dark.
    static let dim = adaptive(
        light: 0x6B7280, dark: 0x8A93A6,
        lightIncreased: 0x4B5563, darkIncreased: 0xAEB6C6
    )

    /// Hairline grouping edge, not a graphical object carrying meaning, so it is
    /// deliberately below 3:1. 1.24:1 light on card, 1.21:1 dark on card;
    /// increased contrast raises those to 2.23:1 and 2.92:1 so the edge is
    /// visible without the card reading as an outlined box.
    static let border = adaptive(
        light: 0xE5E7EB, dark: 0x232838,
        lightIncreased: 0xA8AEBB, darkIncreased: 0x566282
    )

    /// A gain. Matches `WidgetTheme.positive` so app and widgets agree.
    /// 5.02:1 light on card, 4.60:1 light on background, 10.15:1 dark on card.
    /// Increased contrast: 8.15:1 light, 12.60:1 dark.
    static let positive = adaptive(
        light: 0x15803D, dark: 0x4ADE80,
        lightIncreased: 0x0B5C29, darkIncreased: 0x86EFAC
    )

    /// A loss, and also the destructive-action color. Matches
    /// `WidgetTheme.negative`. 6.47:1 light on card, 5.93:1 light on background,
    /// 6.40:1 dark on card. Increased contrast: 10.02:1 light, 9.32:1 dark.
    static let negative = adaptive(
        light: 0xB91C1C, dark: 0xF87171,
        lightIncreased: 0x7F1D1D, darkIncreased: 0xFCA5A5
    )

    /// Exactly-zero change. A 0.00% day rendered in `positive` asserts a gain
    /// that did not happen, and rendering it in `dim` de-emphasises a figure
    /// that sits beside coloured ones — so this is a neutral that reads at the
    /// same weight: 7.56:1 light on card, 6.98:1 dark on card. Increased
    /// contrast: 10.31:1 light, 10.63:1 dark.
    static let neutral = adaptive(
        light: 0x4B5563, dark: 0x9AA3B5,
        lightIncreased: 0x374151, darkIncreased: 0xC2C9D6
    )

    /// Color for a signed change that does not lie about a flat day.
    ///
    /// `isFavorable` is the caller's judgement rather than a re-reading of
    /// `delta`, because a shrinking debt is a gain — direction and desirability
    /// are not the same question.
    static func change(_ delta: Double, isFavorable: Bool) -> Color {
        if delta == 0 { return neutral }
        return isFavorable ? positive : negative
    }

    /// For the common case where up is good.
    static func change(_ delta: Double) -> Color {
        change(delta, isFavorable: delta > 0)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        adaptive(light: light, dark: dark, lightIncreased: light, darkIncreased: dark)
    }

    private static func adaptive(
        light: UInt32,
        dark: UInt32,
        lightIncreased: UInt32,
        darkIncreased: UInt32
    ) -> Color {
        Color(UIColor { traits in
            let increased = traits.accessibilityContrast == .high
            let isDark = traits.userInterfaceStyle == .dark
            let rgb: UInt32
            switch (isDark, increased) {
            case (false, false): rgb = light
            case (false, true): rgb = lightIncreased
            case (true, false): rgb = dark
            case (true, true): rgb = darkIncreased
            }
            return UIColor(rgb: rgb)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
