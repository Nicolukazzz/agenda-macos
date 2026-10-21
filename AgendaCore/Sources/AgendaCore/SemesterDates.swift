import Foundation

/// Default term dates used to prefill the setup wizard; the user can always edit them.
public enum SemesterDates {
    /// `2026-1` → late January to end of May; `2026-2` → late July to end of November.
    public static func guess(for name: String, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let parts = name.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let (year, term) = (parts[0], parts[1])
        let (startMonth, startDay, endMonth, endDay) = term == 1 ? (1, 26, 5, 30) : (7, 27, 11, 28)
        guard
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: startDay)),
            let end = calendar.date(from: DateComponents(year: year, month: endMonth, day: endDay))
        else { return nil }
        return (start, end)
    }
}
