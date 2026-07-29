import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var errorMessage: String?

    private var currency: String { store.snapshot?.currency ?? "USD" }
    private var masked: Bool { store.settings.privacyMode }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.portfolios.count > 1 {
                        portfolioChips
                            .padding(.bottom, 16)
                    }

                    if let errorMessage {
                        Card {
                            Text(errorMessage).foregroundStyle(Theme.negative)
                        }
                        .padding(.bottom, 16)
                    }

                    if let snapshot = store.snapshot {
                        content(for: snapshot)
                    } else {
                        Card {
                            Text("Pull to refresh to load your portfolio from Kubera.")
                                .foregroundStyle(Theme.dim)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Theme.background)
            .navigationTitle("Net Worth")
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    @ViewBuilder
    private func content(for snapshot: PortfolioSnapshot) -> some View {
        heroCard(for: snapshot)
            .padding(.bottom, 12)

        HStack(spacing: 12) {
            statCard("ASSETS", value: snapshot.assetTotal, color: Theme.positive)
            statCard("DEBTS", value: snapshot.debtTotal, color: Theme.negative)
        }

        if !snapshot.allocation.isEmpty {
            SectionTitle("Allocation")
            Card {
                VStack(spacing: 0) {
                    ForEach(snapshot.allocation.sorted { $0.value > $1.value }, id: \.key) { name, pct in
                        allocationRow(name: name, pct: pct)
                    }
                }
            }
        }
    }

    private var portfolioChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.portfolios) { portfolio in
                    let active = portfolio.id == store.selectedPortfolioId
                    Button {
                        Task { await store.selectPortfolio(portfolio.id) }
                    } label: {
                        Text(portfolio.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(active ? Theme.background : Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? Theme.accent : Theme.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func heroCard(for snapshot: PortfolioSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.portfolioName.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(snapshot.netWorth, currency: currency, masked: masked, compact: false))
                    .font(.system(size: 40, weight: .bold))
                    .kerning(-1)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("Updated \(Format.updatedAt(snapshot.updatedAt))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func statCard(_ label: String, value: Double, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(Theme.dim)

                Text(Format.money(value, currency: currency, masked: masked, compact: false))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            }
        }
    }

    private func allocationRow(name: String, pct: Double) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            AllocationBar(fraction: pct / 100)
                .frame(maxWidth: .infinity)

            Text(String(format: "%.1f%%", pct))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func reload() async {
        errorMessage = nil
        do {
            try await store.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AllocationBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(Theme.text)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
