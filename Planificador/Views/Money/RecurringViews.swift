import AgendaCore
import SwiftData
import SwiftUI

/// Subscriptions and salaries: what's fixed each month and when each one charges next.
struct RecurringCard: View {
    @Environment(\.now) private var now
    @Query(sort: \RecurringMoney.title) private var items: [RecurringMoney]
    let display: Currency
    /// Variable spending this month (everything not logged by a subscription).
    let variableSpent: Decimal
    let categories: [MoneyCategory]

    @State private var editing: RecurringMoney?
    @State private var creating = false

    private var active: [RecurringMoney] { items.filter(\.isActive) }

    private func monthly(_ kind: MoneyKind) -> Decimal {
        active.filter { $0.kind == kind }.reduce(0) { total, item in
            total + Money.convert(item.amount * item.cadence.perMonth, from: item.currency, to: display, copPerUSD: MoneyService.currentRate)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Recurring", detail: detail) {
                Button("Add Recurring", systemImage: "plus") { creating = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .help("Add a subscription or a salary")
            }
            Card {
                if items.isEmpty {
                    CardRow(icon: "repeat") {
                        Text("Add Claude, internet or your salary once; Agenda logs them on their day.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(sorted.enumerated()), id: \.element.liveID) { index, item in
                    if index > 0 { CardDivider() }
                    row(item)
                }
            }
        }
        .sheet(isPresented: $creating) { RecurringEditor(item: nil, categories: categories) }
        .sheet(item: $editing) { RecurringEditor(item: $0, categories: categories) }
    }

    private var detail: String? {
        let fixed = monthly(.expense), income = monthly(.income)
        guard fixed > 0 || income > 0 else { return nil }
        var parts: [String] = []
        if income > 0 { parts.append("\(display.format(income)) coming in") }
        if fixed > 0 { parts.append("\(display.format(fixed)) fixed a month") }
        parts.append("\(display.format(variableSpent)) variable this month")
        return parts.joined(separator: " · ")
    }

    /// Active first, soonest charge first.
    private var sorted: [RecurringMoney] {
        items.sorted { a, b in
            if a.isActive != b.isActive { return a.isActive }
            return (a.nextCharge(after: now) ?? .distantFuture) < (b.nextCharge(after: now) ?? .distantFuture)
        }
    }

    private func row(_ item: RecurringMoney) -> some View {
        Button { editing = item } label: {
            HStack(spacing: Theme.Space.m) {
                CategoryIcon(emoji: item.category?.emoji ?? "🔁", colorHex: item.category?.colorHex ?? Theme.Palette.noAreaHex)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(item.title).lineLimit(1)
                    Text(subtitle(item)).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Space.m)
                Text(item.currency.format(item.amount, signed: item.kind == .income))
                    .monospacedDigit()
                    .foregroundStyle(item.kind == .income ? Theme.Palette.success : .primary)
            }
            .opacity(item.isActive ? 1 : 0.5)
            .padding(.horizontal, Theme.Space.m + 2)
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ item: RecurringMoney) -> String {
        let cadence = item.cadence.title
        guard item.isActive else { return "\(cadence) · paused" }
        guard let next = item.nextCharge(after: now) else { return cadence }
        return "\(cadence) · next \(next.agenda(.dateTime.day().month()))"
    }
}

extension Cadence {
    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }
}

/// Create or edit a subscription / salary. Charges due up to today are logged when it's saved.
struct RecurringEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let item: RecurringMoney?
    let categories: [MoneyCategory]

    @State private var title: String
    @State private var kind: MoneyKind
    @State private var amount: Decimal
    @State private var currency: Currency
    @State private var cadence: Cadence
    @State private var start: Date
    @State private var category: MoneyCategory?
    @State private var isActive: Bool
    @State private var confirmingDelete = false

    init(item: RecurringMoney?, categories: [MoneyCategory]) {
        self.item = item
        self.categories = categories
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .expense)
        _amount = State(initialValue: item?.amount ?? 0)
        _currency = State(initialValue: item?.currency ?? .cop)
        _cadence = State(initialValue: item?.cadence ?? .monthly)
        _start = State(initialValue: item?.start ?? .now)
        _category = State(initialValue: item?.category ?? categories.first { $0.tag == "suscripciones" })
        _isActive = State(initialValue: item?.isActive ?? true)
    }

    private var pastCharges: Int {
        guard item == nil else { return 0 }
        let calendar = Calendar.autoupdatingCurrent
        return RecurringSchedule(start: start, cadence: cadence)
            .due(after: nil, through: RecurringSchedule.endOfDay(.now, calendar: calendar), calendar: calendar).count
    }

    var body: some View {
        SheetScaffold(eyebrow: item == nil ? "New Recurring" : "Recurring") {
            TextField("Name — Claude, Internet, Sueldo…", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.Font.editorTitle)

            Card {
                CardRow(icon: "arrow.up.arrow.down") {
                    Text("Type")
                    Spacer()
                    Picker("Type", selection: $kind) {
                        Text("Subscription").tag(MoneyKind.expense)
                        Text("Income").tag(MoneyKind.income)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                CardDivider()
                CardRow(icon: "banknote") {
                    Text("Amount")
                    Spacer()
                    TextField("0", value: $amount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 140)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                CardDivider()
                CardRow(icon: "repeat") {
                    Text("Every")
                    Spacer()
                    Picker("Every", selection: $cadence) {
                        ForEach(Cadence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                CardDivider()
                CardRow(icon: "calendar") {
                    Text(item == nil ? "First charge" : "Charged from")
                    Spacer()
                    DatePicker("First charge", selection: $start, displayedComponents: .date).labelsHidden()
                }
                if pastCharges > 0 {
                    CardNote(text: pastCharges == 1
                             ? "The charge on this date is logged when you save."
                             : "\(pastCharges) charges from this date up to today are logged when you save.")
                }
                CardDivider()
                CardRow(icon: "square.grid.2x2") {
                    Text("Category")
                    Spacer()
                    Picker("Category", selection: $category) {
                        Text("None").tag(nil as MoneyCategory?)
                        ForEach(categories.filter { $0.kind == kind }) { Text("\($0.emoji) \($0.name)").tag(Optional($0)) }
                    }
                    .labelsHidden().fixedSize()
                }
                if item != nil {
                    CardDivider()
                    CardRow(icon: "pause.circle") { CardToggle(title: "Active", isOn: $isActive) }
                    CardNote(text: "Paused items log nothing. Turning one back on starts from its next charge, without catching up.")
                }
            }
            .animation(Theme.Motion.snappy, value: pastCharges)
        } footer: {
            ActionBar(
                destructiveTitle: item == nil ? nil : "Delete",
                onDestructive: { confirmingDelete = true },
                onCancel: { dismiss() },
                primaryTitle: item == nil ? "Add" : "Done",
                primaryDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0,
                onPrimary: save)
        }
        .onChange(of: kind) { if category?.kind != kind { category = nil } }
        .confirmationDialog("Delete “\(title)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let item { context.delete(item) }
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Charges it already logged stay in your history.")
        }
    }

    private func save() {
        let target = item ?? RecurringMoney(title: "", kind: kind, amount: amount, currency: currency, cadence: cadence, start: start, category: category)
        if item == nil { context.insert(target) }
        let resuming = item != nil && !target.isActive && isActive
        let scheduleChanged = item != nil && (target.start != start || target.cadence != cadence)
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        target.amount = amount
        target.currency = currency
        target.cadence = cadence
        target.start = start
        target.category = category
        target.isActive = isActive
        // Resuming or moving the schedule never back-fills missed charges.
        if resuming || scheduleChanged { target.lastCharged = max(target.lastCharged ?? .distantPast, .now) }
        target.chargeDue(copPerUSD: MoneyService.currentRate, in: context)
        try? context.save()
        dismiss()
    }
}
