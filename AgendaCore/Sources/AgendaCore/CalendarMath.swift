import Foundation

/// Calendar helpers with weeks starting on Monday (Colombia).
public struct CalendarMath: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 1
        self.calendar = calendar
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func startOfWeek(containing date: Date) -> Date {
        let day = startOfDay(date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    /// The 7 days of the week containing `date`, Monday first.
    public func weekDays(containing date: Date) -> [Date] {
        let start = startOfWeek(containing: date)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    public func startOfMonth(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    /// Full weeks covering the month of `date` (5 or 6 rows of 7 days), Monday first.
    public func monthGrid(containing date: Date) -> [[Date]] {
        let first = startOfMonth(containing: date)
        let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first)!
        var weekStart = startOfWeek(containing: first)
        var rows: [[Date]] = []
        while weekStart <= last {
            rows.append((0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! })
            weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        }
        return rows
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    public func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    public func add(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    public func add(months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date)!
    }

    /// Minutes since midnight for a date.
    public func minutesIntoDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `day` at `minutes` since midnight.
    public func date(_ day: Date, atMinutes minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: startOfDay(day))!
    }

    /// Same day as `day`, keeping the time of `time`.
    public func date(_ day: Date, keepingTimeOf time: Date) -> Date {
        date(day, atMinutes: minutesIntoDay(time))
    }
}
