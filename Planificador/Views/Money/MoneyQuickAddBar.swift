import AgendaCore
import SwiftData
import SwiftUI

/// Glass bar to log money in one line, for those who like typing: `Peluquería 25k #belleza`,
/// `Claude 20 usd`, `+2m sueldo`. The big "Add Expense" form is the no-syntax way.
struct MoneyQuickAddBar: View {
    @Environment(\.modelContext) private var context
    @AppStorage(MoneySettings.rateKey) private var rate = MoneySettings.defaultRate
    @Query(sort: \MoneyEntry.date, order: .reverse) private var history: [MoneyEntry]
    let categories: [MoneyCategory]

    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: MoneyQuickAddResult {
        MoneyQuickAddParser().parse(text, knownTags: Set(categories.map(\.tag)))
    }

    private var taggedCategory: MoneyCategory? {
        parsed.tag.flatMap { tag in categories.first { $0.tag == tag } }
    }

    /// `+` or an income `#tag` make it income.
    private var kind: MoneyKind {
        parsed.isIncome ? .income : (taggedCategory?.kind ?? .expense)
    }

    private var category: MoneyCategory? { taggedCategory }

    /// The typed currency, else the one this name used last time ("Railway 5" stays dollars), else pesos.
    private var currency: Currency {
        if let typed = parsed.currency { return typed }
        let key = TagSuggester.normalize(parsed.title)
        guard !key.isEmpty else { return .cop }
        return history.first { TagSuggester.normalize($0.title) == key }?.currency ?? .cop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: kind == .income ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(kind == .income ? AnyShapeStyle(Theme.Palette.success) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                TextField("Or type it — “Peluquería 25k #belleza”, “+2m sueldo”", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .font(Theme.Font.rowTitle)
            .padding(.horizontal, Theme.Space.l + 2)
            .padding(.vertical, Theme.Space.m + 3)
            .glassEffect(.regular.interactive(), in: .capsule)

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                preview.padding(.leading, Theme.Space.l).transition(.opacity)
            }
        }
        .animation(Theme.Motion.snappy, value: text.isEmpty)
        .animation(Theme.Motion.snappy, value: kind)
    }

    private var preview: some View {
        HStack(spacing: Theme.Space.s) {
            if let category { Text(category.emoji) }
            Text(displayTitle)
                .font(Theme.Font.caption.weight(.semibold))
                .lineLimit(1)
            if let amount = parsed.amount {
                Text(currency.format(amount, signed: kind == .income))
                    .font(Theme.Font.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(kind == .income ? Theme.Palette.success : .primary)
                if Currency.looksLikeDollars(amount, in: currency) {
                    Text("Pesos? Add “usd” for dollars").font(Theme.Font.caption).foregroundStyle(Theme.Palette.warning)
                }
            } else {
                Text("Add an amount").font(Theme.Font.caption).foregroundStyle(Theme.Palette.warning)
            }
            if let date = parsed.date, !CalendarMath().isSameDay(date, .now) {
                Label(date.agenda(.dateTime.weekday(.wide).day().month()), systemImage: "calendar")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("↩ to add").font(Theme.Font.caption).foregroundStyle(.tertiary)
        }
    }

    private var displayTitle: String {
        parsed.title.isEmpty ? (category?.name ?? kind.title) : parsed.title
    }

    private func add() {
        guard let amount = parsed.amount else { return }
        let math = CalendarMath()
        // A past day keeps the current time so entries of that day still sort by when they were logged.
        let date = parsed.date.map { math.isSameDay($0, .now) ? .now : math.date($0, keepingTimeOf: .now) } ?? .now
        let entry = MoneyEntry(title: displayTitle, kind: kind, amount: amount, currency: currency,
                               copPerUSD: MoneySettings.rate(rate), date: date, category: category)
        withAnimation(Theme.Motion.snappy) { context.insert(entry) }
        try? context.save()
        text = ""
    }
}
