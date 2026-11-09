import AgendaCore
import Charts
import SwiftData
import SwiftUI

/// Money for one month: quick add, spent / earned / balance, where it went, day by day, and every entry.
struct MoneyPage: View {
    @Environment(\.now) private var now
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]
    @Query(sort: \MoneyCategory.sortOrder) private var allCategories: [MoneyCategory]
    @AppStorage(MoneySettings.displayKey) private var displayRaw = Currency.cop.rawValue

    @State private var month = Date.now
    @State private var filter: MoneyCategory?
    @State private var editing: MoneyEntry?

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
            MoneyQuickAddBar(categories: categories)
            summary
            RecurringCard(display: display, variableSpent: variableSpent, categories: categories)
            if monthEntries.isEmpty {
                EmptyState(title: "Nothing logged in \(monthName)", systemImage: "banknote",
                           message: "Type what you spent or earned above. Every entry feeds the totals and charts.")
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
    }

    private var monthName: String { monthStart.agenda(.dateTime.month(.wide).year()) }

    private func shiftMonth(_ delta: Int) {
        withAnimation(Theme.Motion.standard) {
            month = math.add(months: delta, to: monthStart)
            filter = nil
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: Theme.Space.m) {
            StatTile(title: "Spent", systemImage: "arrow.down.right", value: display.format(totals.expense), detail: paceText)
            StatTile(title: "Earned", systemImage: "arrow.up.right", value: display.format(totals.income),
                     detail: totals.income > 0 ? nil : "Log income with “+”", tint: Theme.Palette.success)
            StatTile(title: "Balance", systemImage: "scalemass", value: display.format(totals.net, signed: true),
                     detail: savingsText, tint: totals.net < 0 ? Theme.Palette.danger : .primary)
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

    private var savingsText: String? {
        guard let rate = totals.savingsRate else { return nil }
        let percent = Double(truncating: rate as NSNumber).formatted(.percent.precision(.fractionLength(0)))
        return rate >= 0 ? "Kept \(percent) of income" : "Spent \(percent.replacingOccurrences(of: "-", with: "")) over income"
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
                    donut.frame(width: 180, height: 180)
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
                CategoryIcon(emoji: slice.emoji, colorHex: slice.hex, size: 24)
                Text(slice.name).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(display.format(slice.amount)).monospacedDigit().frame(minWidth: 96, alignment: .trailing)
            }
            .padding(.vertical, Theme.Space.xs)
            .padding(.horizontal, Theme.Space.s)
            .contentShape(Rectangle())
            .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
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
                             colorHex: entry.category?.colorHex ?? Theme.Palette.noAreaHex)
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
            .padding(.horizontal, Theme.Space.m + 2)
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
