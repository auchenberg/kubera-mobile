import SwiftUI
import UIKit
import WidgetKit
import XCTest

final class WidgetThemeTests: XCTestCase {
    // MARK: - Adaptive resolution

    func testEveryColorResolvesDifferentlyPerAppearance() {
        let palette: [(String, Color)] = [
            ("background", WidgetTheme.background),
            ("text", WidgetTheme.text),
            ("dim", WidgetTheme.dim),
            ("border", WidgetTheme.border),
            ("positive", WidgetTheme.positive),
            ("negative", WidgetTheme.negative),
        ]
        for (name, color) in palette {
            XCTAssertNotEqual(
                hex(color, .light),
                hex(color, .dark),
                "\(name) is not adaptive — widgets would keep one appearance's colour"
            )
        }
    }

    func testLightValuesMatchTheAppPalette() {
        XCTAssertEqual(hex(WidgetTheme.background, .light), 0xF4F5F7)
        XCTAssertEqual(hex(WidgetTheme.text, .light), 0x0B0E1A)
        XCTAssertEqual(hex(WidgetTheme.dim, .light), 0x6B7280)
        XCTAssertEqual(hex(WidgetTheme.border, .light), 0xE5E7EB)
        XCTAssertEqual(hex(WidgetTheme.positive, .light), 0x15803D)
        XCTAssertEqual(hex(WidgetTheme.negative, .light), 0xB91C1C)
    }

    func testDarkValuesKeepTheOriginalWidgetPalette() {
        XCTAssertEqual(hex(WidgetTheme.background, .dark), 0x0B0E1A)
        XCTAssertEqual(hex(WidgetTheme.text, .dark), 0xF5F7FA)
        XCTAssertEqual(hex(WidgetTheme.dim, .dark), 0x8A93A6)
        XCTAssertEqual(hex(WidgetTheme.border, .dark), 0x232838)
        XCTAssertEqual(hex(WidgetTheme.positive, .dark), 0x4ADE80)
        XCTAssertEqual(hex(WidgetTheme.negative, .dark), 0xF87171)
    }

    /// The dark-mode green and red are picked to glow on near-black; reusing them
    /// on a near-white background is what made the light previews unreadable.
    func testLightGainAndLossStayDarkEnoughForALightBackground() {
        XCTAssertLessThan(luminance(WidgetTheme.positive, .light), luminance(WidgetTheme.positive, .dark))
        XCTAssertLessThan(luminance(WidgetTheme.negative, .light), luminance(WidgetTheme.negative, .dark))
        XCTAssertLessThan(luminance(WidgetTheme.positive, .light), luminance(WidgetTheme.background, .light))
        XCTAssertLessThan(luminance(WidgetTheme.negative, .light), luminance(WidgetTheme.background, .light))
    }

    func testTextContrastsWithTheBackgroundInBothAppearances() {
        XCTAssertLessThan(luminance(WidgetTheme.text, .light), luminance(WidgetTheme.background, .light))
        XCTAssertGreaterThan(luminance(WidgetTheme.text, .dark), luminance(WidgetTheme.background, .dark))
    }

    // MARK: - Container background

    func testAccessoryFamiliesSkipTheThemedBackground() {
        XCTAssertFalse(WidgetFamily.accessoryInline.usesThemedBackground)
        XCTAssertFalse(WidgetFamily.accessoryCircular.usesThemedBackground)
        XCTAssertFalse(WidgetFamily.accessoryRectangular.usesThemedBackground)
    }

    func testSystemFamiliesUseTheThemedBackground() {
        XCTAssertTrue(WidgetFamily.systemSmall.usesThemedBackground)
        XCTAssertTrue(WidgetFamily.systemMedium.usesThemedBackground)
        XCTAssertTrue(WidgetFamily.systemLarge.usesThemedBackground)
    }

    // MARK: - Helpers

    private func components(
        _ color: Color,
        _ style: UIUserInterfaceStyle
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> UInt32 {
        let rgb = components(color, style)
        let channel = { (value: CGFloat) in UInt32((value * 255).rounded()) }
        return channel(rgb.red) << 16 | channel(rgb.green) << 8 | channel(rgb.blue)
    }

    /// Rough perceptual brightness; enough to assert "darker than" relationships.
    private func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        let rgb = components(color, style)
        return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}
