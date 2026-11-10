import AgendaCore
import SwiftUI

// Money building blocks: formatted amounts, category icons and summary tiles.

/// Where money preferences live in `UserDefaults` (read with `@AppStorage`).
enum MoneySettings {
    /// Pesos per dollar used for new entries. The app is offline, so the user keeps it current.
    static let rateKey = "copPerUSD"
    static let defaultRate = 4000.0
    /// Currency totals and charts are shown in.
    static let displayKey = "moneyDisplayCurrency"

    /// `@AppStorage` holds a Double; rounding to cents drops binary noise (4012.35 stays 4012.35).
    static func rate(_ value: Double) -> Decimal {
        Money.rounded(Decimal(value), for: .usd)
    }
}

extension Currency {
    var title: String { rawValue }
}

extension MoneyKind {
    var title: String { self == .income ? "Income" : "Expense" }
}

/// Category emoji on a soft disc of its color.
struct CategoryIcon: View {
    let emoji: String
    let colorHex: String
    var size: CGFloat = 30

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Theme.Palette.eventFill(colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

/// One headline number with a caption, e.g. "Spent · $ 820.000 · 12% less than October".
struct StatTile: View {
    let title: String
    let systemImage: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Label(title, systemImage: systemImage)
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(detail ?? " ")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// "$ 5 pesos? Use dollars": shown under an amount that is too small to be pesos, with a one-click fix.
struct DollarHint: View {
    let amount: Decimal?
    @Binding var currency: Currency

    var body: some View {
        if let amount, Currency.looksLikeDollars(amount, in: currency) {
            Button {
                withAnimation(Theme.Motion.snappy) { currency = .usd }
            } label: {
                Label("Only \(Currency.cop.format(amount)) pesos? Switch to \(Currency.usd.format(amount))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption.weight(.medium))
                    .foregroundStyle(Theme.Palette.warning)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Theme.Palette.warning.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverLift()
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
