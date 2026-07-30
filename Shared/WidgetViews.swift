import SwiftUI
import WidgetKit

/// The rendering half of every widget, compiled into both targets so the app's
/// previews draw the same views the Home Screen does instead of mockups that
/// drift. Each content view takes its data explicitly — including `family`,
/// since `\.widgetFamily` is an environment key only WidgetKit populates and
/// the app has no way to set it.
///
/// The signed-out state and the widget configuration stay in the extension.
///
/// Colours come from `WidgetTheme`, which resolves per appearance, so every view
/// here works on a light or a dark Home Screen. The Lock Screen accessory
/// families are the exception: they are vibrancy-rendered, so they keep the
/// default foreground styles (`.secondary` at most) — a themed colour there
/// renders as a flat, washed-out block.

// MARK: - Net Worth

struct NetWorthWidgetContent: View {
    let snapshot: PortfolioSnapshot
    let trends: PortfolioTrends?
    let settings: WidgetSettings
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Net worth \(compactMoney(snapshot.netWorth, snapshot))")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("NET")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(compactMoney(snapshot.netWorth, snapshot))
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("NET WORTH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(compactMoney(snapshot.netWorth, snapshot))
                    .font(.system(size: 17, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let day = trends?.day {
                    Text("\(amount(day, snapshot)) (\(Format.percent(day.percent, signed: false))) today")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            // The Kubera dashboard card, two-column: headline left, changes right.
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    title(size: 15)
                    millionsValue(snapshot, size: 30)
                        .foregroundStyle(WidgetTheme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    footer(snapshot)
                }
                Spacer(minLength: 0)
                if hasStatRows {
                    VStack(alignment: .leading, spacing: 10) {
                        statRows(snapshot)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default: // systemSmall — the card condensed, changes stacked below
            VStack(alignment: .leading, spacing: 0) {
                title(size: 13)
                // The spelled-out "Million" format would scale illegibly small
                // at this width; compact keeps it big.
                Text(compactMoney(snapshot.netWorth, snapshot))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hasStatRows {
                    VStack(alignment: .leading, spacing: 6) {
                        statRows(snapshot)
                    }
                } else {
                    footer(snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    private func title(size: CGFloat) -> some View {
        Text("Net Worth")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(WidgetTheme.text)
            .lineLimit(1)
    }

    /// Renders "$1.234 Million" with the currency symbol shrunk and raised, the
    /// way the Kubera dashboard sets it. Masked values have no symbol to split
    /// off, so they fall back to a plain run.
    private func millionsValue(_ snapshot: PortfolioSnapshot, size: CGFloat) -> Text {
        let text = Format.millions(
            snapshot.netWorth,
            currency: snapshot.currency,
            masked: settings.privacyMode
        )
        guard let split = symbolSplit(text) else {
            return Text(text).font(.system(size: size, weight: .bold))
        }
        return Text(split.symbol)
            .font(.system(size: size * 0.55, weight: .bold))
            .baselineOffset(size * 0.3)
            + Text(split.rest)
            .font(.system(size: size, weight: .bold))
    }

    /// Everything ahead of the first digit is the currency symbol ("$", "kr ",
    /// "DKK "). Nil when the string starts with a digit or carries none at all.
    private func symbolSplit(_ text: String) -> (symbol: String, rest: String)? {
        guard let firstDigit = text.firstIndex(where: { $0.isNumber }),
              firstDigit != text.startIndex else {
            return nil
        }
        return (String(text[..<firstDigit]), String(text[firstDigit...]))
    }

    @ViewBuilder
    private func statRows(_ snapshot: PortfolioSnapshot) -> some View {
        if let trends {
            if let day = trends.day {
                statRow("1 DAY", day, snapshot)
            }
            if let ytd = trends.ytd {
                statRow("YTD", ytd, snapshot)
            }
        }
    }

    private func statRow(
        _ label: String,
        _ change: PortfolioTrends.Change,
        _ snapshot: PortfolioSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(WidgetTheme.dim)
            // Percentages stay visible in privacy mode: a ratio reveals no balance.
            Text("\(amount(change, snapshot)) (\(Format.percent(change.percent, signed: false)))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(change.amount >= 0 ? WidgetTheme.positive : WidgetTheme.negative)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
    }

    /// While the stat column is empty (no trends at all, or a log too young to
    /// have any references), the footer picks up the timestamp line instead.
    @ViewBuilder
    private func footer(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.portfolioName)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
                .lineLimit(1)
            if !hasStatRows {
                Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(1)
            }
        }
    }

    private var hasStatRows: Bool {
        guard let trends else { return false }
        return trends.day != nil || trends.ytd != nil
    }

    private func amount(_ change: PortfolioTrends.Change, _ snapshot: PortfolioSnapshot) -> String {
        Format.money(
            change.amount,
            currency: snapshot.currency,
            masked: settings.privacyMode,
            compact: true,
            signed: true
        )
    }

    private func compactMoney(_ value: Double, _ snapshot: PortfolioSnapshot) -> String {
        Format.money(
            value,
            currency: snapshot.currency,
            masked: settings.privacyMode,
            compact: true
        )
    }
}

// MARK: - CAGR

struct CagrWidgetContent: View {
    let snapshot: PortfolioSnapshot
    let trends: PortfolioTrends?
    let comps: MarketComps?
    let settings: WidgetSettings
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CAGR • YTD")
                .font(.system(size: 10, weight: .semibold))
                .kerning(1)
                .foregroundStyle(WidgetTheme.dim)

            if let ytd = trends?.ytd {
                Spacer(minLength: 2)
                Text(Format.percent(ytd.percent))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: ytd.amount))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("NET WORTH")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(WidgetTheme.dim)
            } else {
                // No reference points yet: the log needs at least a prior day.
                // The comps below still work, so keep the row.
                Spacer(minLength: 0)
                Text("Growth appears once a day of history has been collected.")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetTheme.dim)
                if comps == nil {
                    Spacer(minLength: 0)
                    Text(snapshot.portfolioName)
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
            }

            if let comps {
                Spacer(minLength: 6)
                compsRow(comps)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func compsRow(_ comps: MarketComps) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let sp500 = comps.sp500 {
                miniStat("S&P 500", sp500)
            }
            if let dowJones = comps.dowJones {
                // "DOW JONES" truncates at a third of a small widget's width.
                miniStat("DOW", dowJones)
            }
            if let btc = comps.btc {
                miniStat("BTC", btc)
            }
        }
    }

    /// Three labels have to share a small widget's width, so both lines shrink
    /// rather than truncate.
    private func miniStat(_ label: String, _ percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(WidgetTheme.dim)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(Format.percent(percent))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(for: percent))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for value: Double) -> Color {
        value >= 0 ? WidgetTheme.positive : WidgetTheme.negative
    }
}

// MARK: - Assets vs Debts

struct AssetsDebtsWidgetContent: View {
    let snapshot: PortfolioSnapshot
    let settings: WidgetSettings
    let family: WidgetFamily

    var body: some View {
        let total = max(snapshot.assetTotal, 1)
        let debtRatio = min(max(snapshot.debtTotal / total, 0), 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ASSETS")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(WidgetTheme.dim)
                    Text(money(snapshot.assetTotal, snapshot))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.positive)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("DEBTS")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1)
                        .foregroundStyle(WidgetTheme.dim)
                    Text(money(snapshot.debtTotal, snapshot))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.negative)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WidgetTheme.positive)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(WidgetTheme.negative)
                        .frame(width: max(geo.size.width * debtRatio, snapshot.debtTotal > 0 ? 6 : 0))
                }
            }
            .frame(height: 10)

            HStack {
                Text("NET \(money(snapshot.netWorth, snapshot))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                Spacer()
                Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func money(_ amount: Double, _ snapshot: PortfolioSnapshot) -> String {
        Format.money(amount, currency: snapshot.currency, settings: settings)
    }
}

// MARK: - Backgrounds

extension WidgetFamily {
    /// Whether the family draws `WidgetTheme.background` as its container
    /// background. Lock Screen accessories get their backdrop from the system
    /// and render their content with vibrancy, so filling them with an opaque
    /// theme colour paints over the Lock Screen instead of blending into it.
    var usesThemedBackground: Bool {
        switch self {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            return false
        default:
            return true
        }
    }
}
