import Foundation

/// What the Today widget shows: the next week of classes and events, and the open tasks with a date.
/// The app writes it as JSON whenever the calendar or the tasks change; the widget only reads it,
/// and works out "now" and "next" for each moment by itself, so it stays right with Agenda closed.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public var title: String
        public var location: String
        public var colorHex: String
        public var start: Date
        public var end: Date
        /// Part of the class timetable, not an event the user made.
        public var isClass: Bool
        public init(title: String, location: String, colorHex: String, start: Date, end: Date, isClass: Bool) {
            self.title = title; self.location = location; self.colorHex = colorHex; self.start = start; self.end = end; self.isClass = isClass
        }
    }

    public struct Due: Codable, Equatable, Sendable {
        public var title: String
        public var colorHex: String
        public var due: Date
        /// False for tasks due "that day", stored at 23:59.
        public var hasTime: Bool
        public init(title: String, colorHex: String, due: Date, hasTime: Bool) {
            self.title = title; self.colorHex = colorHex; self.due = due; self.hasTime = hasTime
        }
    }

    public var updatedAt: Date
    /// Timed events, soonest first.
    public var events: [Event]
    /// Open tasks, soonest first. Overdue ones included.
    public var tasks: [Due]

    public init(updatedAt: Date, events: [Event], tasks: [Due]) {
        self.updatedAt = updatedAt
        self.events = events.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        self.tasks = tasks.sorted { ($0.due, $0.title) < ($1.due, $1.title) }
    }

    public static let empty = TodaySnapshot(updatedAt: .distantPast, events: [], tasks: [])
    /// The snapshot holds this many days ahead; older than that, it has nothing true left to say.
    public static let horizonDays = 7

    // MARK: Reading it at a moment

    /// The event going on at `date`, if any.
    public func current(at date: Date) -> Event? {
        events.first { $0.start <= date && $0.end > date }
    }

    /// Events still to start on the day of `date`.
    public func upcomingToday(at date: Date, calendar: Calendar = .current) -> [Event] {
        events.filter { $0.start > date && calendar.isDate($0.start, inSameDayAs: date) }
    }

    /// The first event to start after `date`, on any day.
    public func next(after date: Date) -> Event? {
        events.first { $0.start > date }
    }

    /// Tasks to deal with on the day of `date`: overdue first, then that day's.
    public func dueToday(at date: Date, calendar: Calendar = .current) -> [Due] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return [] }
        return tasks.filter { $0.due < tomorrow }
    }

    /// A task with a time is overdue once it passes; a task for "that day" is overdue the day after.
    public func isOverdue(_ task: Due, at date: Date, calendar: Calendar = .current) -> Bool {
        task.hasTime ? task.due < date : task.due < calendar.startOfDay(for: date)
    }

    /// Moments after `date` when what the widget shows changes: an event starts or ends, a task's time passes, a day begins.
    public func refreshDates(after date: Date, limit: Int = 40, calendar: Calendar = .current) -> [Date] {
        var moments = events.flatMap { [$0.start, $0.end] } + tasks.filter(\.hasTime).map(\.due)
        var day = calendar.startOfDay(for: date)
        for _ in 0..<Self.horizonDays {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            moments.append(next)
            day = next
        }
        return Array(Set(moments.filter { $0 > date })).sorted().prefix(limit).map { $0 }
    }

    // MARK: JSON

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TodaySnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TodaySnapshot.self, from: data)
    }
}
