import SwiftUI
import UIKit

/// App palette. Colors resolve per trait collection so they follow the system
/// appearance without every view reading `\.colorScheme`.
enum Theme {
    static let background = adaptive(light: 0xF4F5F7, dark: 0x0A0C12)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x151823)
    static let text = adaptive(light: 0x0B0E1A, dark: 0xF5F7FA)
    static let dim = adaptive(light: 0x6B7280, dark: 0x8A93A6)
    static let border = adaptive(light: 0xE5E7EB, dark: 0x232838)
    static let accent = adaptive(light: 0x0B0E1A, dark: 0xF5F7FA)
    static let positive = adaptive(light: 0x15803D, dark: 0x4ADE80)
    static let negative = adaptive(light: 0xB91C1C, dark: 0xF87171)
    static let widgetPreviewBg = adaptive(light: 0x0B0E1A, dark: 0x151823)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
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
