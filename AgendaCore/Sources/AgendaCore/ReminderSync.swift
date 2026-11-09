import Foundation

/// A due date the way Reminders stores it: a day, plus an hour and minute when the reminder has a time.
/// Comparing components (not `Date`s) keeps all-day reminders stable across time zones and seconds.
public struct ReminderDue: Codable, Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int?
    public var minute: Int?

    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
        self.year = year; self.month = month; self.day = day; self.hour = hour; self.minute = minute
    }

    public var hasTime: Bool { hour != nil }

    /// From an app task: all-day tasks keep only the day.
    public init(date: Date, hasTime: Bool, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1,
                  hour: hasTime ? (parts.hour ?? 0) : nil,
                  minute: hasTime ? (parts.minute ?? 0) : nil)
    }

    /// From a reminder's `dueDateComponents`. Nil when the components don't name a day.
    public init?(components: DateComponents) {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        self.init(year: year, month: month, day: day, hour: components.hour, minute: components.hour == nil ? nil : (components.minute ?? 0))
    }

    /// Components for `EKReminder.dueDateComponents`: only the day for all-day reminders.
    public var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    /// The app's representation: the exact time, or 23:59 of the day for all-day tasks.
    public func appDate(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 23, minute: hour == nil ? 59 : (minute ?? 0)))
    }
}

/// App priority (0 none, 1 high `!`, 2 urgent `!!`) to EventKit's 0…9 scale (1 highest, 5 medium, 9 lowest).
public enum ReminderPriority {
    public static func eventKit(fromApp priority: Int) -> Int {
        switch priority {
        case 2...: 1
        case 1: 5
        default: 0
        }
    }

    public static func app(fromEventKit priority: Int) -> Int {
        switch priority {
        case 1...4: 2
        case 5...9: 1
        default: 0
        }
    }
}

/// The fields kept in step between a task and its reminder.
public struct ReminderFields: Codable, Equatable, Sendable {
    public var title: String
    public var notes: String
    public var due: ReminderDue?
    public var isDone: Bool
    public var priority: Int

    public init(title: String, notes: String, due: ReminderDue?, isDone: Bool, priority: Int) {
        self.title = title; self.notes = notes; self.due = due; self.isDone = isDone; self.priority = priority
    }
}

/// Three-way merge between the task (app), the reminder (remote) and the last synced state (base).
/// Per field: whichever side changed since the last sync wins; when both changed, the app wins.
/// Without a base (first link) the app wins everything.
public enum ReminderMerge {
    public struct Result: Equatable, Sendable {
        public var fields: ReminderFields
        /// The task must be updated to `fields`.
        public var updatesApp: Bool
        /// The reminder must be updated to `fields`.
        public var updatesRemote: Bool
    }

    public static func merge(app: ReminderFields, remote: ReminderFields, base: ReminderFields?) -> Result {
        guard let base else {
            return Result(fields: app, updatesApp: false, updatesRemote: app != remote)
        }
        func pick<Value: Equatable>(_ key: KeyPath<ReminderFields, Value>) -> Value {
            app[keyPath: key] != base[keyPath: key] ? app[keyPath: key] : remote[keyPath: key]
        }
        let fields = ReminderFields(
            title: pick(\.title), notes: pick(\.notes), due: pick(\.due),
            isDone: pick(\.isDone), priority: pick(\.priority))
        return Result(fields: fields, updatesApp: fields != app, updatesRemote: fields != remote)
    }
}

/// Reminder ids the app removed itself, newest last, so a task brought back with ⌘Z gets a new
/// reminder instead of being treated as "deleted on the iPhone". Capped so it never grows unbounded.
public struct RemovedReminders: Equatable, Sendable {
    public private(set) var ids: [String]
    public let limit: Int

    public init(_ ids: [String] = [], limit: Int = 500) {
        self.limit = limit
        self.ids = Array(ids.suffix(limit))
    }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public mutating func insert(_ id: String) {
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > limit { ids.removeFirst(ids.count - limit) }
    }
}

/// Guard against mass deletion: if iCloud hiccups and many reminders look gone at once,
/// deleting the matching tasks would lose data. Small batches pass; big sudden drops don't.
public enum ReminderDeletionGuard {
    public static func allows(deleting count: Int, ofLinked linked: Int) -> Bool {
        count <= max(3, linked / 2)
    }
}
