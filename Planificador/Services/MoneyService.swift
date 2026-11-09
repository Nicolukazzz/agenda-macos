import AgendaCore
import AppKit
import Foundation
import KeyboardShortcuts
import OSLog
import SwiftData
import WidgetKit

/// App-side money chores: logging due subscriptions, the widget snapshot, and `agenda://money/add` links.
@MainActor
enum MoneyService {
    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "Money")

    static var currentRate: Decimal {
        let stored = UserDefaults.standard.object(forKey: MoneySettings.rateKey) as? Double
        return MoneySettings.rate(stored ?? MoneySettings.defaultRate)
    }

    static var displayCurrency: Currency {
        UserDefaults.standard.string(forKey: MoneySettings.displayKey).flatMap(Currency.init(rawValue:)) ?? .cop
    }

    /// Logs every subscription or salary charge due by now. Safe to call often.
    static func chargeRecurring(_ context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<RecurringMoney>(predicate: #Predicate { $0.isActive })) else { return }
        let added = items.reduce(0) { $0 + $1.chargeDue(copPerUSD: currentRate, in: context) }
        guard added > 0 else { return }
        try? context.save()
        log.info("Logged \(added) recurring charges")
    }

    /// Repeats a widget shortcut. Returns false for links that aren't money shortcuts.
    @discardableResult
    static func handle(_ url: URL, context: ModelContext) -> Bool {
        guard let shortcut = MoneySnapshot.Shortcut(url: url) else { return false }
        let categories = (try? context.fetch(FetchDescriptor<MoneyCategory>())) ?? []
        let category = shortcut.categoryTag.flatMap { tag in categories.first { $0.tag == tag } }
        context.insert(MoneyEntry(title: shortcut.title, kind: shortcut.kind, amount: shortcut.amount, currency: shortcut.currency,
                                  copPerUSD: currentRate, category: category))
        try? context.save()
        return true
    }

    // MARK: Widget snapshot

    /// `~/Library/Application Support/com.nicolas.agenda/money-widget.json`, next to the store.
    /// The sandboxed widget reads it through a read-only file exception for this folder.
    static var snapshotURL: URL {
        StoreLoader.storeURL.deletingLastPathComponent().appending(path: "money-widget.json")
    }

    static func snapshot(_ context: ModelContext, now: Date = .now) -> MoneySnapshot {
        let math = CalendarMath()
        let display = displayCurrency
        let monthStart = math.startOfMonth(containing: now)
        let today = math.startOfDay(now)
        let entries = (try? context.fetch(FetchDescriptor<MoneyEntry>(
            predicate: #Predicate { $0.date >= monthStart }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let month = entries.filter { $0.date <= now }
        let totals = MoneyTotals(month.map(\.value), in: display)

        let slices = Dictionary(grouping: month.filter { $0.kind == .expense }) { $0.category?.persistentModelID }
            .map { _, items in
                let category = items.first?.category
                return MoneySnapshot.Slice(name: category?.name ?? "Other", emoji: category?.emoji ?? "•",
                                           colorHex: category?.colorHex ?? "#6B7A90", amount: MoneyTotals(items.map(\.value), in: display).expense)
            }
            .sorted { $0.amount > $1.amount }

        // Shortcuts come from the last 60 days of hand-logged entries.
        let since = math.add(days: -60, to: today)
        let recent = (try? context.fetch(FetchDescriptor<MoneyEntry>(
            predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let shortcuts = MoneyShortcuts.frequent(recent.filter { $0.recurring == nil }.map {
            .init(title: $0.title, emoji: $0.category?.emoji ?? "•", amount: $0.amount, currency: $0.currency, kind: $0.kind, categoryTag: $0.category?.tag)
        })

        let recurring = (try? context.fetch(FetchDescriptor<RecurringMoney>(predicate: #Predicate { $0.isActive }))) ?? []
        let next = recurring.compactMap { item in item.nextCharge(after: now).map { (item, $0) } }.min { $0.1 < $1.1 }

        return MoneySnapshot(
            updatedAt: now, monthTitle: monthStart.formatted(.dateTime.month(.wide).locale(.agenda)), currency: display,
            spent: totals.expense, earned: totals.income,
            spentToday: MoneyTotals(month.filter { $0.date >= today && $0.kind == .expense }.map(\.value), in: display).expense,
            slices: slices, shortcuts: shortcuts,
            nextCharge: next.map { .init(title: $0.0.title, date: $0.1) })
    }

    /// Rewrites the widget's JSON and asks WidgetKit to redraw, only when something changed.
    static func refreshWidgets(_ context: ModelContext) {
        guard !AppEnvironment.isPreview else { return }
        var current = snapshot(context)
        if let old = try? MoneySnapshot.decode(Data(contentsOf: snapshotURL)) {
            current.updatedAt = old.updatedAt
            guard old != current else { return }
        }
        current.updatedAt = .now
        do {
            try current.encoded().write(to: snapshotURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            log.error("Widget snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension KeyboardShortcuts.Name {
    /// Global "log an expense" hotkey. No default: the user picks one in Settings.
    static let logMoney = Self("logMoney")
}

extension MoneyService {
    /// From any app: bring Agenda forward with the new-expense form open.
    static func listenForHotkey() {
        KeyboardShortcuts.onKeyUp(for: .logMoney) {
            if let url = URL(string: "agenda://money/new") { NSWorkspace.shared.open(url) }
        }
    }
}
