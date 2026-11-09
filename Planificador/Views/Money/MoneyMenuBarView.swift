import AgendaCore
import AppKit
import SwiftData
import SwiftUI

/// Menu bar panel: log money from any app without opening the main window.
struct MoneyMenuBarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]
    @Query(sort: \MoneyCategory.sortOrder) private var categories: [MoneyCategory]

    private let math = CalendarMath()

    var body: some View {
        let display = MoneyService.displayCurrency
        let now = Date.now
        let month = entries.prefix { $0.date >= math.startOfMonth(containing: now) }.filter { $0.date <= now }
        let totals = MoneyTotals(month.map(\.value), in: display)
        let today = MoneyTotals(month.filter { $0.date >= math.startOfDay(now) }.map(\.value), in: display).expense

        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "Today", systemImage: "cup.and.saucer", value: display.format(today))
                StatTile(title: now.agenda(.dateTime.month(.wide)).capitalized, systemImage: "calendar",
                         value: display.format(totals.expense),
                         detail: totals.income > 0 ? "Balance \(display.format(totals.net, signed: true))" : nil)
            }
            MoneyQuickAddBar(categories: categories.filter { !$0.isArchived })

            if !month.isEmpty {
                Card {
                    ForEach(Array(month.prefix(5).enumerated()), id: \.element.liveID) { index, entry in
                        if index > 0 { CardDivider() }
                        CardRow {
                            Text(entry.category?.emoji ?? "•")
                            Text(entry.title).lineLimit(1)
                            Spacer()
                            Text(entry.currency.format(entry.kind == .income ? entry.amount : -entry.amount, signed: entry.kind == .income))
                                .monospacedDigit()
                                .foregroundStyle(entry.kind == .income ? Theme.Palette.success : .primary)
                        }
                    }
                }
            }

            HStack {
                Button("Open Money") {
                    appState.selection = .money
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .secondaryAction()
                Spacer()
                Button("Quit Agenda") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 460)
        .onAppear { MoneyCategory.seedDefaults(in: context) }
    }
}
