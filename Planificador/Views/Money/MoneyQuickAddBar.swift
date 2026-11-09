import AgendaCore
import SwiftData
import SwiftUI

/// Glass bar to log money in one line: `Peluquería 25k #belleza`, `Claude 20 usd`, `+2m sueldo`.
/// Below it, Expense/Income and category chips for when typing a `#tag` is slower than clicking.
struct MoneyQuickAddBar: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @AppStorage(MoneySettings.rateKey) private var rate = MoneySettings.defaultRate
    let categories: [MoneyCategory]

    @State private var text = ""
    @State private var manualKind = MoneyKind.expense
    @State private var manualCategory: MoneyCategory?
    @FocusState private var focused: Bool

    private var parsed: MoneyQuickAddResult {
        MoneyQuickAddParser().parse(text, knownTags: Set(categories.map(\.tag)))
    }

    private var taggedCategory: MoneyCategory? {
        parsed.tag.flatMap { tag in categories.first { $0.tag == tag } }
    }

    /// `+` or an income `#tag` decide; otherwise the segmented control does.
    private var kind: MoneyKind {
        parsed.isIncome ? .income : (taggedCategory?.kind ?? manualKind)
    }

    private var category: MoneyCategory? {
        taggedCategory ?? (manualCategory?.kind == kind ? manualCategory : nil)
    }

    private var currency: Currency { parsed.currency ?? .cop }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: kind == .income ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(kind == .income ? AnyShapeStyle(Theme.Palette.success) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                TextField("Spent or earned — “Peluquería 25k #belleza”, “Claude 20 usd”, “+2m sueldo”", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .glassEffect(.regular.interactive(), in: .capsule)

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                preview.padding(.leading, Theme.Space.l).transition(.opacity)
            }

            HStack(spacing: Theme.Space.m) {
                Picker("Type", selection: Binding(get: { kind }, set: { manualKind = $0 })) {
                    ForEach(MoneyKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ChipRow {
                    ForEach(categories.filter { $0.kind == kind }) { item in
                        Chip(title: "\(item.emoji) \(item.name)", colorHex: item.colorHex, isSelected: category === item, showsDot: false) {
                            manualCategory = manualCategory === item ? nil : item
                        }
                    }
                }
            }
        }
        .animation(Theme.Motion.snappy, value: text.isEmpty)
        .animation(Theme.Motion.snappy, value: kind)
        .onAppear(perform: takeCommand)
        .onChange(of: appState.pendingCommand) { takeCommand() }
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
        manualCategory = nil
    }

    private func takeCommand() {
        guard appState.pendingCommand == .newMoneyEntry else { return }
        appState.pendingCommand = nil
        focused = true
    }
}
