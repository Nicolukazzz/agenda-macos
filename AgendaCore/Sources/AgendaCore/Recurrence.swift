import Foundation

/// Weekly repetition for calendar blocks (class schedules).
public struct WeeklyRecurrence: Codable, Hashable, Sendable {
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    /// Last day (inclusive) an occurrence may start on, usually the semester's end date.
    public var until: Date

    public init(weekdays: Set<Int>, until: Date) {
        self.weekdays = weekdays
        self.until = until
    }
}
