import AgendaCore
import SwiftData
import SwiftUI

/// Edit one expense or income in place. Changes apply live; ⌘Z undoes them.
struct MoneyEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var entry: MoneyEntry
    let categories: [MoneyCategory]

    @State private var confirmingDelete = false

    private var kind: Binding<MoneyKind> {
        Binding(get: { entry.kind }, set: { newKind in
            entry.kind = newKind
            if entry.category?.kind != newKind { entry.category = nil }
        })
    }

    private var currency: Binding<Currency> {
        Binding(get: { entry.currency }, set: { entry.currency = $0 })
    }

    var body: some View {
        SheetScaffold(eyebrow: entry.kind.title) {
            TextField("Title", text: $entry.title)
                .textFieldStyle(.plain)
                .font(Theme.Font.editorTitle)

            Card {
                CardRow(icon: "arrow.up.arrow.down") {
                    Text("Type")
                    Spacer()
                    Picker("Type", selection: kind) {
                        ForEach(MoneyKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                CardDivider()
                CardRow(icon: "banknote") {
                    Text("Amount")
                    Spacer()
                    TextField("0", value: $entry.amount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 140)
                    Picker("Currency", selection: currency) {
                        ForEach(Currency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if entry.currency == .usd {
                    CardDivider()
                    CardRow(icon: "arrow.left.arrow.right") {
                        Text("Pesos per dollar")
                        Spacer()
                        TextField("4000", value: $entry.copPerUSD, format: .number)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 140)
                    }
                    CardNote(text: "≈ \(Currency.cop.format(entry.value.amount(in: .cop))). The rate from the day you logged it, so past months don’t change when the dollar moves.")
                }
                CardDivider()
                CardRow(icon: "square.grid.2x2") {
                    Text("Category")
                    Spacer()
                    Picker("Category", selection: $entry.category) {
                        Text("None").tag(nil as MoneyCategory?)
                        ForEach(categories.filter { $0.kind == entry.kind }) {
                            Text("\($0.emoji) \($0.name)").tag(Optional($0))
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                CardDivider()
                CardRow(icon: "calendar") {
                    Text("Date")
                    Spacer()
                    DatePicker("Date", selection: $entry.date, displayedComponents: .date).labelsHidden()
                }
            }
            .animation(Theme.Motion.snappy, value: entry.currency)
        } footer: {
            ActionBar(
                destructiveTitle: "Delete",
                onDestructive: { confirmingDelete = true },
                cancelTitle: nil,
                primaryTitle: "Done",
                primaryDisabled: entry.amount <= 0 || (entry.currency == .usd && entry.copPerUSD <= 0)
            ) {
                try? context.save()
                dismiss()
            }
        }
        .confirmationDialog("Delete “\(entry.title)”?", isPresented: $confirmingDelete) {
            Button("Delete \(entry.kind.title)", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
        }
    }
}
