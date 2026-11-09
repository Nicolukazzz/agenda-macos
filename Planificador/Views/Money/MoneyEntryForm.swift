import AgendaCore
import SwiftData
import SwiftUI

/// The simple way to log money: a big amount, a name, a category tile and a day. No syntax to learn.
/// Typing a name used before fills in its last amount and category. "Repeats" turns it into a recurring item.
struct MoneyEntryForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(MoneySettings.rateKey) private var rate = MoneySettings.defaultRate
    @Query(sort: \MoneyCategory.sortOrder) private var allCategories: [MoneyCategory]
    @Query(sort: \MoneyEntry.date, order: .reverse) private var history: [MoneyEntry]

    @State private var kind: MoneyKind
    @State private var amountText = ""
    @State private var currency = Currency.cop
    @State private var title = ""
    @State private var category: MoneyCategory?
    @State private var date = Date.now
    @State private var repeats = false
    @State private var every = 1
    @State private var cadence = Cadence.monthly
    @FocusState private var amountFocused: Bool

    private let math = CalendarMath()

    init(kind: MoneyKind = .expense) {
        _kind = State(initialValue: kind)
    }

    private var categories: [MoneyCategory] { allCategories.filter { !$0.isArchived && $0.kind == kind } }

    /// Accepts `25000`, `25.000`, `25k`, `1,5m`, `3.99`.
    private var amount: Decimal? {
        MoneyQuickAddParser().parse(amountText, knownTags: []).amount
    }

    /// Past entries whose name starts like what's being typed, newest first, one per name.
    private var matches: [MoneyEntry] {
        let query = TagSuggester.normalize(title)
        guard !query.isEmpty else { return [] }
        var seen = Set<String>()
        return history.filter { entry in
            let key = TagSuggester.normalize(entry.title)
            return entry.kind == kind && key.hasPrefix(query) && key != query && seen.insert(key).inserted
        }
        .prefix(4).map { $0 }
    }

    var body: some View {
        SheetScaffold(eyebrow: kind == .income ? "New Income" : "New Expense", width: 600) {
            Picker("Type", selection: $kind) {
                Text("Expense").tag(MoneyKind.expense)
                Text("Income").tag(MoneyKind.income)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            amountField
            nameField
            categoryGrid
            dayAndRepeat
        } footer: {
            ActionBar(onCancel: { dismiss() }, primaryTitle: repeats ? "Add Recurring" : "Add", primaryDisabled: amount == nil, onPrimary: save)
        }
        .onAppear { amountFocused = true }
        .onChange(of: kind) { if category?.kind != kind { category = nil } }
    }

    // MARK: Amount

    private var amountField: some View {
        VStack(spacing: Theme.Space.xs) {
            Picker("Currency", selection: $currency) {
                Text("COP $").tag(Currency.cop)
                Text("USD US$").tag(Currency.usd)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField("0", text: $amountText)
                .textFieldStyle(.plain)
                .font(Theme.Font.hero)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($amountFocused)
                .onSubmit(save)
            Text(amount.map { currency.format($0) } ?? "Type the amount — 25000, 25k or 25.000")
                .font(Theme.Font.rowDetail)
                .foregroundStyle(amount == nil ? .tertiary : .secondary)
                .contentTransition(.numericText())
                .animation(Theme.Motion.snappy, value: amountText)
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField(kind == .income ? "From what? — Sueldo, freelance…" : "What was it? — Peluquería, gasolina…", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.Font.rowTitle)
                .padding(.horizontal, Theme.Space.l)
                .frame(height: Theme.Size.bigButtonHeight)
                .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .onSubmit(save)
            if !matches.isEmpty {
                ChipRow {
                    ForEach(matches) { entry in
                        Chip(title: "\(entry.category?.emoji ?? "•") \(entry.title) · \(entry.currency.format(entry.amount))",
                             colorHex: entry.category?.colorHex, isSelected: false, showsDot: false) { reuse(entry) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.snappy, value: matches.isEmpty)
    }

    /// Fills the form from a past entry: the "same as last time" shortcut.
    private func reuse(_ entry: MoneyEntry) {
        title = entry.title
        category = entry.category
        currency = entry.currency
        amountText = "\(entry.amount)"
    }

    // MARK: Category

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 4), spacing: Theme.Space.s) {
            ForEach(categories) { item in
                let selected = category === item
                Button {
                    withAnimation(Theme.Motion.snappy) { category = selected ? nil : item }
                } label: {
                    VStack(spacing: Theme.Space.xs) {
                        Text(item.emoji).font(.system(size: 26))
                        Text(item.name).font(Theme.Font.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(selected ? AnyShapeStyle(Color(hex: item.colorHex).opacity(0.3)) : Theme.Palette.cardFill,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(selected ? Color(hex: item.colorHex) : .clear, lineWidth: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLift(scale: 1.04)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Day and repeat

    private var dayAndRepeat: some View {
        Card {
            CardRow(icon: "calendar") {
                Chip(title: "Today", isSelected: math.isSameDay(date, .now), showsDot: false) { date = .now }
                Chip(title: "Yesterday", isSelected: math.isSameDay(date, math.add(days: -1, to: .now)), showsDot: false) {
                    date = math.add(days: -1, to: .now)
                }
                Spacer()
                DatePill(date: $date, showsIcon: false)
            }
            CardDivider()
            CardRow(icon: "repeat") { CardToggle(title: "Repeats", isOn: $repeats.animation(Theme.Motion.snappy)) }
            if repeats {
                CardDivider()
                CardRow(icon: "clock.arrow.circlepath") {
                    Text("Every")
                    Stepper("\(every)", value: $every, in: 1...12).monospacedDigit().fixedSize()
                    Spacer()
                    Picker("Every", selection: $cadence) {
                        ForEach(Cadence.allCases, id: \.self) { Text($0.unit(plural: every > 1)).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                CardNote(text: "Agenda logs it on its own from \(date.agenda(.dateTime.day().month())), \(Cadence.describe(cadence, every: every)).")
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let finalTitle = name.isEmpty ? (category?.name ?? kind.title) : name
        let day = math.isSameDay(date, .now) ? .now : math.date(date, keepingTimeOf: .now)
        if repeats {
            let item = RecurringMoney(title: finalTitle, kind: kind, amount: amount, currency: currency, cadence: cadence, start: day, category: category)
            item.every = every
            context.insert(item)
            item.chargeDue(copPerUSD: MoneySettings.rate(rate), in: context)
        } else {
            context.insert(MoneyEntry(title: finalTitle, kind: kind, amount: amount, currency: currency,
                                      copPerUSD: MoneySettings.rate(rate), date: day, category: category))
        }
        try? context.save()
        dismiss()
    }
}

extension Cadence {
    func unit(plural: Bool) -> String {
        switch self {
        case .weekly: plural ? "weeks" : "week"
        case .monthly: plural ? "months" : "month"
        case .yearly: plural ? "years" : "year"
        }
    }

    /// "every month", "every 2 months".
    static func describe(_ cadence: Cadence, every: Int) -> String {
        every == 1 ? "every \(cadence.unit(plural: false))" : "every \(every) \(cadence.unit(plural: true))"
    }
}
