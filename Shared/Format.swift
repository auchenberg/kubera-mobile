import Foundation
import SwiftUI
import UIKit

enum Format {
    static let masked = "••••••"

    /// "$1.24M" style compact currency, or full grouping when compact is off.
    static func money(
        _ amount: Double,
        currency: String,
        masked isMasked: Bool,
        compact: Bool,
        signed: Bool = false
    ) -> String {
        if isMasked { return masked }

        let sign = signed && amount > 0 ? "+" : (amount < 0 ? "-" : "")
        let absolute = abs(amount)
        let symbol = currencySymbol(for: currency)

        if compact, absolute >= 100_000 {
            let (value, suffix): (Double, String) =
                absolute >= 1_000_000_000 ? (absolute / 1_000_000_000, "B")
                : absolute >= 1_000_000 ? (absolute / 1_000_000, "M")
                : (absolute / 1_000, "K")
            let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
            return "\(sign)\(symbol)\(String(format: "%.\(digits)f", value))\(suffix)"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        if let formatted = formatter.string(from: NSNumber(value: absolute)) {
            return "\(sign)\(formatted)"
        }
        return "\(sign)\(symbol)\(Int(absolute))"
    }

    /// Widget-facing variant that reads masking and compaction from settings.
    static func money(
        _ amount: Double,
        currency: String,
        settings: WidgetSettings,
        compactOverride: Bool? = nil,
        signed: Bool = false
    ) -> String {
        money(
            amount,
            currency: currency,
            masked: settings.privacyMode,
            compact: compactOverride ?? settings.compactNumbers,
            signed: signed
        )
    }

    /// Kubera-dashboard headline format: "$1.234 Million", "$1.2 Billion",
    /// full grouping below one million ("$74,000"). Masked → "••••••".
    static func millions(_ amount: Double, currency: String, masked isMasked: Bool) -> String {
        if isMasked { return masked }

        let absolute = abs(amount)
        guard absolute >= 1_000_000 else {
            return money(amount, currency: currency, masked: false, compact: false)
        }

        let sign = amount < 0 ? "-" : ""
        let symbol = currencySymbol(for: currency)
        let (value, suffix): (Double, String) =
            absolute >= 1_000_000_000 ? (absolute / 1_000_000_000, " Billion")
            : (absolute / 1_000_000, " Million")
        return "\(sign)\(symbol)\(String(format: "%.3f", value))\(suffix)"
    }

    /// "+64.1%", "(0.02%)"-style percent: 2 decimals below 0.1, 1 decimal below
    /// 100, else none, with trailing zeros dropped. signed prefixes "+" for positives.
    static func percent(_ value: Double, signed: Bool = true) -> String {
        let sign = signed && value > 0 ? "+" : (value < 0 ? "-" : "")
        let magnitude = abs(value)
        let digits = magnitude < 0.1 ? 2 : (magnitude < 100 ? 1 : 0)

        var text = String(format: "%.\(digits)f", magnitude)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return "\(sign)\(text)%"
    }

    private static func currencySymbol(for code: String) -> String {
        switch code {
        case "USD", "CAD", "AUD", "NZD", "HKD", "SGD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        case "INR": return "₹"
        case "DKK", "SEK", "NOK": return "kr "
        default: return "\(code) "
        }
    }

    static func updatedAt(_ unixSeconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: unixSeconds))
    }
}

/// Widget palette, resolved per trait collection the same way `Theme` is in the
/// app, so a widget follows the Home Screen's appearance instead of forcing
/// dark. WidgetKit renders the extension with the environment's traits, so a
/// dynamic `UIColor` resolves correctly in both appearances — and in the app's
/// in-app previews, which draw these same views.
///
/// The values match `Theme`'s so app and widgets agree. Light-mode
/// positive/negative are deliberately darker than their dark-mode counterparts:
/// #4ADE80 and #F87171 are unreadable on a near-white background.
enum WidgetTheme {
    static let background = adaptive(light: 0xF4F5F7, dark: 0x0B0E1A)
    static let text = adaptive(light: 0x0B0E1A, dark: 0xF5F7FA)
    static let dim = adaptive(light: 0x6B7280, dark: 0x8A93A6)
    static let border = adaptive(light: 0xE5E7EB, dark: 0x232838)
    static let positive = adaptive(light: 0x15803D, dark: 0x4ADE80)
    static let negative = adaptive(light: 0xB91C1C, dark: 0xF87171)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
