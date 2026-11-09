import AgendaCore
import Charts
import Pow
import SwiftData
import SwiftUI

/// Money for one month: quick add, spent / earned / balance, where it went, day by day, and every entry.
struct MoneyPage: View {
    @Environment(\.now) private var now
    @Environment(AppState.self) private var appState
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]
    @Query private var recurring: [RecurringMoney]
    /// Normalized titles of habit suggestions the user said "Not now" to.
    @AppStorage("moneyDismissedSuggestions") private var dismissedRaw = ""
    @Query(sort: \MoneyCategory.sortOrder) private var allCategories: [MoneyCategory]
    @AppStorage(MoneySettings.displayKey) private var displayRaw = Currency.cop.rawValue

    @State private var month = Date.now
    @State private var filter: MoneyCategory?
    @State private var editing: MoneyEntry?
    @State private var newEntryKind: MoneyKind?
    @State private var suggestionToAdd: RecurringSuggestion?

    private let math = CalendarMath()

    private var display: Currency { Currency(rawValue: displayRaw) ?? .cop }
    private var categories: [MoneyCategory] { allCategories.filter { !$0.isArchived } }
    private var monthStart: Date { math.startOfMonth(containing: month) }
    private var nextMonthStart: Date { math.add(months: 1, to: monthStart) }
    private var isCurrentMonth: Bool { math.isSameMonth(month, now) }

    private func entries(from start: Date, to end: Date) -> [MoneyEntry] {
        entries.filter { $0.date >= start && $0.date < end }
    }

    private var monthEntries: [MoneyEntry] { entries(from: monthStart, to: nextMonthStart) }
    private var totals: MoneyTotals { MoneyTotals(monthEntries.map(\.value), in: display) }
    private var variableSpent: Decimal { MoneyTotals(monthEntries.filter { $0.recurring == nil }.map(\.value), in: display).expense }

    var body: some View {
        PageContent {
            hero
            HStack(spacing: Theme.Space.m) {
                BigButton(title: "Add Expense", systemImage: "minus.circle.fill") { newEntryKind = .expense }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                BigButton(title: "Add Income", systemImage: "plus.circle.fill", tint: Theme.Palette.success, prominent: false) { newEntryKind = .income }
            }
            MoneyQuickAddBar(categories: categories)
            ForEach(suggestions, id: \.key) { suggestionCard($0) }
            RecurringCard(display: display, variableSpent: variableSpent, categories: categories)
            if monthEntries.isEmpty {
                EmptyState(title: "Nothing logged in \(monthName)", systemImage: "banknote",
                           message: "Click Add Expense or Add Income. Every entry feeds the totals and charts.")
            } else {
                if totals.expense > 0 {
                    categoryCard
                    dailyCard
                }
                entryList
            }
        }
        .navigationTitle("Money")
        .navigationSubtitle(monthName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Previous Month", systemImage: "chevron.left") { shiftMonth(-1) }
                Button("This Month") { month = now; filter = nil }.disabled(isCurrentMonth)
                Button("Next Month", systemImage: "chevron.right") { shiftMonth(1) }.disabled(isCurrentMonth)
                Picker("Show in", selection: $displayRaw) {
                    ForEach(Currency.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .help("Currency for totals and charts")
            }
        }
        .sheet(item: $editing) { MoneyEntryEditor(entry: $0, categories: categories) }
        .sheet(item: $newEntryKind) { MoneyEntryForm(kind: $0) }
        .sheet(item: Binding(get: { suggestionToAdd.map(IdentifiedSuggestion.init) }, set: { suggestionToAdd = $0?.value })) {
            RecurringEditor(item: nil, categories: categories, suggestion: $0.value)
        }
        .onAppear(perform: takeCommand)
        .onChange(of: appState.pendingCommand) { takeCommand() }
    }

    private var monthName: String { monthStart.agenda(.dateTime.month(.wide).year()) }

    private func shiftMonth(_ delta: Int) {
        withAnimation(Theme.Motion.standard) {
            month = math.add(months: delta, to: monthStart)
            filter = nil
        }
    }

    // MARK: Hero

    /// The month at a glance: what went out, big and centered, with what came in and what's left.
    private var hero: some View {
        VStack(spacing: Theme.Space.s) {
            Text(isCurrentMonth ? "Spent this month" : "Spent in \(monthStart.agenda(.dateTime.month(.wide)))")
                .font(Theme.Font.rowDetail.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(display.format(totals.expense))
                .font(Theme.Font.hero)
                .changeEffect(.shine(duration: 0.8), value: totals.expense)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let paceText {
                Text(paceText).font(Theme.Font.rowDetail).foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Space.xl) {
                heroFigure("Earned", display.format(totals.income), tint: Theme.Palette.success)
                Divider().frame(height: 32)
                heroFigure("Balance", display.format(totals.net, signed: true), tint: totals.net < 0 ? Theme.Palette.danger : .primary)
                if let savingsText {
                    Divider().frame(height: 32)
                    heroFigure("Kept", savingsText, tint: .primary)
                }
            }
            .padding(.top, Theme.Space.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .padding(.horizontal, Theme.Space.l)
        .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.panel + 6, style: .continuous))
        .animation(Theme.Motion.standard, value: totals.expense)
    }

    private func heroFigure(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: Theme.Space.xxs) {
            Text(title).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
    }

    /// This month so far against the previous month up to the same day (whole months when looking back).
    private var paceText: String? {
        let cutoff = isCurrentMonth ? now : nextMonthStart
        let previousStart = math.add(months: -1, to: monthStart)
        let previous = MoneyTotals(entries(from: previousStart, to: math.add(months: -1, to: cutoff)).map(\.value), in: display).expense
        guard previous > 0 else { return nil }
        let change = Double(truncating: ((totals.expense - previous) / previous) as NSNumber)
        let name = previousStart.agenda(.dateTime.month(.wide))
        let when = isCurrentMonth ? "\(name) by this day" : name
        if abs(change) < 0.01 { return "Same as \(when)" }
        return "\(abs(change).formatted(.percent.precision(.fractionLength(0)))) \(change > 0 ? "more" : "less") than \(when)"
    }

    /// Share of income left, e.g. "85%". Nil without income.
    private var savingsText: String? {
        guard let rate = totals.savingsRate else { return nil }
        return Double(truncating: rate as NSNumber).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: Habits

    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: "|").map(String.init)) }

    /// Things logged by hand at a steady rhythm that aren't recurring yet. At most two at a time.
    private var suggestions: [RecurringSuggestion] {
        let since = math.add(days: -400, to: now)
        let items = entries.filter { $0.recurring == nil && $0.date >= since && $0.date <= now }.map {
            RecurringDetector.Item(title: $0.title, date: $0.date, amount: $0.amount, currency: $0.currency, kind: $0.kind, categoryTag: $0.category?.tag)
        }
        let excluded = dismissed.union(recurring.map { TagSuggester.normalize($0.title) })
        return Array(RecurringDetector.suggestions(from: items, excluding: excluded, now: now, calendar: math.calendar).prefix(2))
    }

    private func suggestionCard(_ suggestion: RecurringSuggestion) -> some View {
        let category = categories.first { $0.tag == suggestion.categoryTag }
        return HStack(spacing: Theme.Space.l) {
            CategoryIcon(emoji: category?.emoji ?? "✨", colorHex: category?.colorHex ?? "#8E6CF0", size: 46)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("\(suggestion.title) looks like a habit")
                    .font(Theme.Font.sectionTitle)
                Text("You logged it \(suggestion.occurrences) times, about \(Cadence.describe(suggestion.cadence, every: suggestion.every)) (\(suggestion.currency.format(suggestion.amount))). Make it recurring so Agenda logs it for you?")
                    .font(Theme.Font.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(spacing: Theme.Space.xs) {
                Button("Make Recurring") { suggestionToAdd = suggestion }
                    .primaryAction()
                Button("Not Now") {
                    withAnimation(Theme.Motion.snappy) { dismissedRaw = (dismissed.union([suggestion.key])).sorted().joined(separator: "|") }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(Theme.Space.l)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Color.accentColor.opacity(0.3))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func takeCommand() {
        guard appState.pendingCommand == .newMoneyEntry else { return }
        appState.pendingCommand = nil
        newEntryKind = .expense
    }

    // MARK: Where it went

    private struct Slice: Identifiable {
        let id: PersistentIdentifier?
        let category: MoneyCategory?
        let amount: Decimal
        var name: String { category?.name ?? "No category" }
        var emoji: String { category?.emoji ?? "•" }
        var hex: String { category?.colorHex ?? Theme.Palette.noAreaHex }
    }

    private var slices: [Slice] {
        let expenses = monthEntries.filter { $0.kind == .expense }
        return Dictionary(grouping: expenses) { $0.category?.persistentModelID }
            .map { id, items in
                Slice(id: id, category: items.first?.category, amount: MoneyTotals(items.map(\.value), in: display).expense)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("Where It Went", detail: filter.map { "Showing \($0.name) · click again to show all" })
            Card {
                HStack(alignment: .center, spacing: Theme.Space.xl) {
                    donut.frame(width: 200, height: 200)
                    VStack(spacing: 0) {
                        ForEach(slices) { slice in legendRow(slice) }
                    }
                }
                .padding(Theme.Space.l)
            }
        }
    }

    private var donut: some View {
        let data = slices
        return Chart(data) { slice in
            SectorMark(angle: .value("Amount", Double(truncating: slice.amount as NSNumber)),
                       innerRadius: .ratio(0.64), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(Color(hex: slice.hex))
                .opacity(filter == nil || filter?.persistentModelID == slice.id ? 1 : 0.25)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: Theme.Space.xxs) {
                Text("Spent").font(Theme.Font.caption).foregroundStyle(.secondary)
                Text(display.format(totals.expense))
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, Theme.Space.xl)
            }
        }
        .animation(Theme.Motion.standard, value: filter)
    }

    private func legendRow(_ slice: Slice) -> some View {
        let share = totals.expense > 0 ? Double(truncating: (slice.amount / totals.expense) as NSNumber) : 0
        let selected = filter != nil && filter?.persistentModelID == slice.id
        return Button {
            withAnimation(Theme.Motion.snappy) { filter = selected ? nil : slice.category }
        } label: {
            HStack(spacing: Theme.Space.s) {
                CategoryIcon(emoji: slice.emoji, colorHex: slice.hex, size: 30)
                Text(slice.name).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(display.format(slice.amount)).monospacedDigit().frame(minWidth: 96, alignment: .trailing)
            }
            .font(Theme.Font.rowTitle)
            .padding(.vertical, Theme.Space.xs + 2)
            .padding(.horizontal, Theme.Space.s)
            .contentShape(Rectangle())
            .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .hoverHighlight(inset: 0)
        }
        .buttonStyle(.plain)
        .disabled(slice.category == nil)
    }

    // MARK: Day by day

    private var dailyCard: some View {
        let expenses = monthEntries.filter { $0.kind == .expense && (filter == nil || $0.category === filter) }
        let byDay = Dictionary(grouping: expenses) { math.startOfDay($0.date) }
            .map { (day: $0.key, amount: Double(truncating: MoneyTotals($0.value.map(\.value), in: display).expense as NSNumber)) }
        let elapsed = isCurrentMonth ? math.calendar.component(.day, from: now)
            : math.calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let total = byDay.reduce(0) { $0 + $1.amount }
        let average = display.format(Decimal(total / Double(max(elapsed, 1))))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("Day by Day", detail: "≈ \(average) a day")
            Card {
                Chart(byDay, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Spent", item.amount))
                        .foregroundStyle((filter.map { Color(hex: $0.colorHex) } ?? .accentColor).gradient)
                        .cornerRadius(3)
                }
                .chartXScale(domain: monthStart...math.add(days: -1, to: nextMonthStart))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let amount = value.as(Double.self) { Text(compact(amount)) } }
                    }
                }
                .frame(height: 150)
                .padding(Theme.Space.l)
            }
        }
    }

    /// Axis labels: `80 mil`, `1,2 M`.
    private func compact(_ amount: Double) -> String {
        amount.formatted(.number.notation(.compactName).locale(Locale(identifier: "es_CO")))
    }

    // MARK: Entries

    private var entryList: some View {
        let shown = monthEntries.filter { filter == nil || $0.category === filter }
        let days = Dictionary(grouping: shown) { math.startOfDay($0.date) }.sorted { $0.key > $1.key }
        return ForEach(days, id: \.key) { day, items in
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                let net = MoneyTotals(items.map(\.value), in: display).net
                SectionHeader(dayTitle(day), detail: display.format(net, signed: true))
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.liveID) { index, entry in
                        if index > 0 { CardDivider() }
                        row(entry)
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if math.isSameDay(day, now) { return "Today" }
        if math.isSameDay(day, math.add(days: -1, to: now)) { return "Yesterday" }
        return day.agenda(.dateTime.weekday(.wide).day().month())
    }

    private func row(_ entry: MoneyEntry) -> some View {
        Button { editing = entry } label: {
            HStack(spacing: Theme.Space.m) {
                CategoryIcon(emoji: entry.category?.emoji ?? (entry.kind == .income ? "💰" : "•"),
                             colorHex: entry.category?.colorHex ?? Theme.Palette.noAreaHex, size: 38)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(entry.title).lineLimit(1)
                    if entry.category != nil || entry.recurring != nil {
                        HStack(spacing: Theme.Space.xs) {
                            if entry.recurring != nil { Image(systemName: "repeat").accessibilityLabel("Recurring") }
                            if let category = entry.category { Text(category.name) }
                        }
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(entry.currency.format(entry.kind == .income ? entry.amount : -entry.amount, signed: entry.kind == .income))
                        .monospacedDigit()
                        .foregroundStyle(entry.kind == .income ? Theme.Palette.success : .primary)
                    if entry.currency != display {
                        Text("≈ \(display.format(entry.value.amount(in: display)))")
                            .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .font(Theme.Font.rowTitle)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { editing = entry }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
        }
    }

    @Environment(\.modelContext) private var context

    private func delete(_ entry: MoneyEntry) {
        withAnimation(Theme.Motion.snappy) { context.delete(entry) }
        try? context.save()
    }
}

extension MoneyKind: @retroactive Identifiable {
    public var id: Self { self }
}

/// `RecurringSuggestion` lives in AgendaCore; sheets need an identity.
private struct IdentifiedSuggestion: Identifiable {
    let value: RecurringSuggestion
    var id: String { value.key }
}
