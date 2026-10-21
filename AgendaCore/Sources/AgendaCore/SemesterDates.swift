import Foundation

/// A term covers its half of the year: `AAAA-1` is January–June and `AAAA-2` is July–December.
/// The user doesn't need exact start dates; recurring classes simply live inside this range.
public enum SemesterDates {
    /// First day of the term and last day (inclusive, at start of day).
    public static func range(for name: String, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let parts = name.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...2).contains(parts[1]) else { return nil }
        let (year, term) = (parts[0], parts[1])
        let (startMonth, endMonth, endDay) = term == 1 ? (1, 6, 30) : (7, 12, 31)
        guard
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)),
            let end = calendar.date(from: DateComponents(year: year, month: endMonth, day: endDay))
        else { return nil }
        return (start, end)
    }
}
