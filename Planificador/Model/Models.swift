import AgendaCore
import Foundation
import SwiftData

/// A university term, e.g. `2026-2`, mapped to its folder under the classes root.
@Model
final class Semester {
    var name: String
    var folderPath: String
    var startDate: Date
    var endDate: Date
    /// Recess weeks and holidays: class blocks are skipped inside these ranges.
    var breaks: [DateInterval]
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Area.semester)
    var areas: [Area] = []

    init(name: String, folderPath: String, startDate: Date, endDate: Date, breaks: [DateInterval] = [], isActive: Bool = true) {
        self.name = name
        self.folderPath = folderPath
        self.startDate = startDate
        self.endDate = endDate
        self.breaks = breaks
        self.isActive = isActive
        self.createdAt = .now
    }

    /// Keeps the dates on the term's half of the year (`AAAA-1` Jan–Jun, `AAAA-2` Jul–Dec).
    /// Also fixes semesters created by the first build, which asked for exact class dates.
    func normalizeDates() {
        guard let range = SemesterDates.range(for: name) else { return }
        if startDate != range.start { startDate = range.start }
        if endDate != range.end { endDate = range.end }
    }

    var sortedAreas: [Area] {
        areas.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// A course with its folder, or a personal area (`#personal`) with no folder.
@Model
final class Area {
    var name: String
    var tag: String
    var colorHex: String
    /// Absolute path to the course folder; nil for personal areas.
    var folderPath: String?
    var semester: Semester?
    var isArchived: Bool
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \Block.area)
    var blocks: [Block] = []

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.area)
    var tasks: [TaskItem] = []

    init(name: String, tag: String, colorHex: String, folderPath: String?, semester: Semester?, sortOrder: Int) {
        self.name = name
        self.tag = tag
        self.colorHex = colorHex
        self.folderPath = folderPath
        self.semester = semester
        self.isArchived = false
        self.sortOrder = sortOrder
    }

    var folderURL: URL? {
        folderPath.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// True when the area should have a folder but it was renamed or moved away.
    var isFolderMissing: Bool {
        guard let folderPath else { return false }
        var isDirectory: ObjCBool = false
        return !FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory) || !isDirectory.boolValue
    }
}

/// A time block in the week calendar: a class, an appointment or scheduled work on a task.
@Model
final class Block {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var location: String
    var area: Area?
    var recurrence: WeeklyRecurrence?
    /// Start-of-day dates where a recurring block does not happen (cancelled or moved "only this time").
    var exceptionDates: [Date]
    var linkedTask: TaskItem?

    /// Part of the class timetable (a course's weekly slot from the Schedule tab or an import).
    /// The month view hides these; it shows only what the user creates (tasks and one-off events).
    var isClassSchedule: Bool {
        recurrence != nil && area?.folderPath != nil
    }

    init(title: String, start: Date, end: Date, area: Area? = nil, recurrence: WeeklyRecurrence? = nil, location: String = "", notes: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
        self.area = area
        self.recurrence = recurrence
        self.exceptionDates = []
    }
}

@Model
final class TaskItem {
    var title: String
    var notes: String
    var dueDate: Date?
    /// When false the task is due at the end of `dueDate`'s day.
    var dueHasTime: Bool
    var area: Area?
    /// 0 normal, 1 high, 2 urgent.
    var priority: Int
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date

    /// "Create reminder": keep this task in step with Apple Reminders (and so the iPhone, via iCloud).
    var createsReminder: Bool = false
    /// `EKReminder.calendarItemIdentifier` of the linked reminder.
    var reminderID: String?
    /// `calendarItemExternalIdentifier`, the fallback when iCloud re-identifies the reminder.
    var reminderExternalID: String?
    /// The reminder's list. A missing reminder only counts as deleted while its list still exists.
    var reminderListID: String?
    /// JSON of the `ReminderFields` at the last sync: the base of the three-way merge.
    var reminderSnapshot: Data?

    @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
    var subtasks: [Subtask] = []

    @Relationship(deleteRule: .nullify, inverse: \Block.linkedTask)
    var scheduledBlocks: [Block] = []

    init(title: String, dueDate: Date? = nil, dueHasTime: Bool = false, area: Area? = nil, priority: Int = 0, notes: String = "") {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.area = area
        self.priority = priority
        self.isDone = false
        self.createdAt = .now
    }
}

@Model
final class Subtask {
    var title: String
    var isDone: Bool
    var order: Int
    var task: TaskItem?

    init(title: String, order: Int) {
        self.title = title
        self.isDone = false
        self.order = order
    }
}

extension TaskItem {
    var reminderFieldsSnapshot: ReminderFields? {
        get { reminderSnapshot.flatMap { try? JSONDecoder().decode(ReminderFields.self, from: $0) } }
        set { reminderSnapshot = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    func clearReminderLink() {
        reminderID = nil
        reminderExternalID = nil
        reminderListID = nil
        reminderSnapshot = nil
    }
}

/// A bucket for money: "Gasolina", "Suscripciones", "Sueldo". Expense and income categories are separate.
@Model
final class MoneyCategory {
    var name: String
    /// Quick-add tag without `#`, normalized like area tags.
    var tag: String
    var emoji: String
    var colorHex: String
    var kindRaw: String
    var sortOrder: Int
    var isArchived: Bool

    @Relationship(deleteRule: .nullify, inverse: \MoneyEntry.category)
    var entries: [MoneyEntry] = []

    init(name: String, emoji: String, colorHex: String, kind: MoneyKind, sortOrder: Int) {
        self.name = name
        self.tag = TagSuggester.normalize(name)
        self.emoji = emoji
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.isArchived = false
    }

    var kind: MoneyKind {
        get { MoneyKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    static let defaults: [(name: String, emoji: String, hex: String, kind: MoneyKind)] = [
        ("Comida", "🍔", "#F0A33A", .expense),
        ("Gasolina", "⛽", "#E5534B", .expense),
        ("Transporte", "🚕", "#D9822B", .expense),
        ("Pareja", "❤️", "#E85D9A", .expense),
        ("Belleza", "💈", "#B565D9", .expense),
        ("Suscripciones", "🔁", "#8E6CF0", .expense),
        ("Hogar", "🏠", "#4F7BF7", .expense),
        ("Universidad", "🎓", "#2BA7C9", .expense),
        ("Ocio", "🎮", "#3FB27F", .expense),
        ("Compras", "🛍️", "#C9A227", .expense),
        ("Salud", "💊", "#5AA469", .expense),
        ("Otros", "📦", "#6B7A90", .expense),
        ("Sueldo", "💼", "#2E9E6A", .income),
        ("Freelance", "💻", "#3B8FD9", .income),
        ("Regalo", "🎁", "#E07AB8", .income),
        ("Otros ingresos", "💰", "#7A8B6B", .income),
    ]

    /// Inserts the starter categories once, the first time money is used.
    static func seedDefaults(in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<MoneyCategory>())) == 0 else { return }
        for (index, item) in defaults.enumerated() {
            context.insert(MoneyCategory(name: item.name, emoji: item.emoji, colorHex: item.hex, kind: item.kind, sortOrder: index))
        }
    }
}

/// One expense or income. Amounts are `Decimal` so pesos and cents never drift.
@Model
final class MoneyEntry {
    var title: String
    var kindRaw: String
    var amount: Decimal
    var currencyRaw: String
    /// Pesos per dollar when the entry was made; totals in either currency use this, not today's rate.
    var copPerUSD: Decimal
    /// When the money moved (the day matters, the time only orders entries within it).
    var date: Date
    var createdAt: Date
    var category: MoneyCategory?
    /// Set when the entry was logged automatically by a subscription or a salary.
    var recurring: RecurringMoney?

    init(title: String, kind: MoneyKind, amount: Decimal, currency: Currency, copPerUSD: Decimal, date: Date = .now, category: MoneyCategory? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyRaw = currency.rawValue
        self.copPerUSD = copPerUSD
        self.date = date
        self.createdAt = .now
        self.category = category
    }

    var kind: MoneyKind {
        get { MoneyKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .cop }
        set { currencyRaw = newValue.rawValue }
    }

    var value: MoneyValue { MoneyValue(kind: kind, amount: amount, currency: currency, copPerUSD: copPerUSD) }
}

/// Money that repeats: subscriptions (Claude, internet) and income (salary).
/// On its day it logs a real `MoneyEntry`, so months show what was actually charged, never a forecast.
@Model
final class RecurringMoney {
    var title: String
    var kindRaw: String
    var amount: Decimal
    var currencyRaw: String
    var cadenceRaw: String
    /// First charge; later ones are counted from it.
    var start: Date
    /// Date of the newest charge already logged.
    var lastCharged: Date?
    var isActive: Bool
    var category: MoneyCategory?

    @Relationship(deleteRule: .nullify, inverse: \MoneyEntry.recurring)
    var entries: [MoneyEntry] = []

    init(title: String, kind: MoneyKind, amount: Decimal, currency: Currency, cadence: Cadence, start: Date, category: MoneyCategory?) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyRaw = currency.rawValue
        self.cadenceRaw = cadence.rawValue
        self.start = start
        self.isActive = true
        self.category = category
    }

    var kind: MoneyKind {
        get { MoneyKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .cop }
        set { currencyRaw = newValue.rawValue }
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var schedule: RecurringSchedule { RecurringSchedule(start: start, cadence: cadence) }

    func nextCharge(after date: Date = .now) -> Date? {
        schedule.next(after: max(date, lastCharged ?? .distantPast), calendar: .autoupdatingCurrent)
    }

    /// Logs every charge due up to `now` that isn't logged yet. Returns how many were added.
    @discardableResult
    func chargeDue(now: Date = .now, copPerUSD: Decimal, in context: ModelContext) -> Int {
        guard isActive, amount > 0 else { return 0 }
        let calendar = Calendar.autoupdatingCurrent
        let dates = schedule.due(after: lastCharged, through: RecurringSchedule.endOfDay(now, calendar: calendar), calendar: calendar)
        for date in dates {
            let entry = MoneyEntry(title: title, kind: kind, amount: amount, currency: currency, copPerUSD: copPerUSD, date: date, category: category)
            entry.recurring = self
            context.insert(entry)
        }
        if let last = dates.last { lastCharged = last }
        return dates.count
    }
}

enum AgendaSchema {
    static let models: [any PersistentModel.Type] = [Semester.self, Area.self, Block.self, TaskItem.self, Subtask.self, MoneyCategory.self, MoneyEntry.self, RecurringMoney.self]
}

extension PersistentModel {
    /// Stable identity for SwiftUI lists while the object is alive. `persistentModelID` can repeat
    /// for objects that haven't been saved yet, which breaks `ForEach` diffing.
    var liveID: ObjectIdentifier { ObjectIdentifier(self) }
}
