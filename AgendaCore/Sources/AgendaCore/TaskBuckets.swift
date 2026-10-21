import Foundation

/// Sections of the task list, in display order.
public enum TaskBucket: Int, CaseIterable, Sendable, Comparable {
    case overdue, today, tomorrow, thisWeek, later, someday

    public static func < (lhs: TaskBucket, rhs: TaskBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This Week"
        case .later: "Later"
        case .someday: "No Date"
        }
    }

    /// Tasks without a time are due at the end of their day, so they're never overdue during that day.
    public static func bucket(due: Date?, hasTime: Bool, now: Date, math: CalendarMath) -> TaskBucket {
        guard let due else { return .someday }
        let today = math.startOfDay(now)
        let dueDay = math.startOfDay(due)
        let isPast = hasTime ? due < now : dueDay < today
        if isPast { return .overdue }
        if dueDay == today { return .today }
        if dueDay == math.add(days: 1, to: today) { return .tomorrow }
        let weekEnd = math.add(days: 7, to: math.startOfWeek(containing: now))
        return dueDay < weekEnd ? .thisWeek : .later
    }
}
