import Foundation

/// The calendar-relevant part of a block, decoupled from SwiftData so it can be tested.
public struct BlockSnapshot: Sendable, Equatable {
    public var id: String
    public var start: Date
    public var end: Date
    public var recurrence: WeeklyRecurrence?
    /// Start-of-day dates skipped for this recurring block.
    public var exceptionDates: [Date]
    /// Recurring class blocks also skip semester breaks.
    public var skipsBreaks: Bool

    public init(id: String, start: Date, end: Date, recurrence: WeeklyRecurrence? = nil, exceptionDates: [Date] = [], skipsBreaks: Bool = true) {
        self.id = id
        self.start = start
        self.end = end
        self.recurrence = recurrence
        self.exceptionDates = exceptionDates
        self.skipsBreaks = skipsBreaks
    }
}

/// One concrete appearance of a block on a given day.
public struct Occurrence: Sendable, Equatable, Hashable {
    public var blockID: String
    public var start: Date
    public var end: Date
    public var isRecurring: Bool
}

public enum RecurrenceExpander {
    /// Occurrences overlapping `interval`, sorted by start.
    public static func occurrences(
        of blocks: [BlockSnapshot],
        in interval: DateInterval,
        breaks: [DateInterval] = [],
        math: CalendarMath = CalendarMath()
    ) -> [Occurrence] {
        var result: [Occurrence] = []
        for block in blocks {
            guard let rule = block.recurrence else {
                if block.end > interval.start && block.start < interval.end {
                    result.append(Occurrence(blockID: block.id, start: block.start, end: block.end, isRecurring: false))
                }
                continue
            }
            let duration = block.end.timeIntervalSince(block.start)
            let startMinutes = math.minutesIntoDay(block.start)
            let firstDay = max(math.startOfDay(block.start), math.startOfDay(interval.start))
            let lastDay = min(math.startOfDay(rule.until), math.startOfDay(interval.end))
            let exceptions = Set(block.exceptionDates.map(math.startOfDay))

            var day = firstDay
            while day <= lastDay {
                let weekday = math.calendar.component(.weekday, from: day)
                let skipped = exceptions.contains(day)
                    || (block.skipsBreaks && breaks.contains { $0.contains(day) && day < $0.end })
                if rule.weekdays.contains(weekday), !skipped {
                    let start = math.date(day, atMinutes: startMinutes)
                    let end = start.addingTimeInterval(duration)
                    if end > interval.start && start < interval.end {
                        result.append(Occurrence(blockID: block.id, start: start, end: end, isRecurring: true))
                    }
                }
                day = math.add(days: 1, to: day)
            }
        }
        return result.sorted { ($0.start, $0.blockID) < ($1.start, $1.blockID) }
    }
}

/// Side-by-side columns for overlapping events in a day (week view).
public enum OverlapLayout {
    public struct Slot: Equatable, Sendable {
        public var column: Int
        public var columnCount: Int
    }

    /// Returns a slot per input index. Events that overlap share a cluster and split its width.
    public static func slots(for ranges: [(start: Date, end: Date)]) -> [Slot] {
        let order = ranges.indices.sorted { (ranges[$0].start, ranges[$0].end) < (ranges[$1].start, ranges[$1].end) }
        var slots = [Slot](repeating: Slot(column: 0, columnCount: 1), count: ranges.count)
        var cluster: [Int] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for index in cluster { slots[index].columnCount = max(1, columnEnds.count) }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for index in order {
            let range = ranges[index]
            if range.start >= clusterEnd { closeCluster() }
            if let free = columnEnds.firstIndex(where: { $0 <= range.start }) {
                columnEnds[free] = range.end
                slots[index].column = free
            } else {
                columnEnds.append(range.end)
                slots[index].column = columnEnds.count - 1
            }
            cluster.append(index)
            clusterEnd = max(clusterEnd, range.end)
        }
        closeCluster()
        return slots
    }
}
