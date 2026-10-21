import AgendaCore
import Foundation
import SwiftData

/// One block occurrence ready to draw.
struct CalendarItem: Identifiable, Hashable {
    let block: Block
    let occurrence: Occurrence

    var id: String { "\(occurrence.blockID)|\(occurrence.start.timeIntervalSinceReferenceDate)" }
    var start: Date { occurrence.start }
    var end: Date { occurrence.end }
    var isRecurring: Bool { occurrence.isRecurring }
    var colorHex: String { block.area?.colorHex ?? CoursePalette.hexColors.last! }

    static func == (lhs: CalendarItem, rhs: CalendarItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum CalendarFeed {
    /// Unique per live model object. (`persistentModelID` descriptions can collide for unsaved objects.)
    static func key(for object: AnyObject) -> String { String(UInt(bitPattern: ObjectIdentifier(object).hashValue), radix: 36) }

    /// Expands blocks into occurrences overlapping `interval`, skipping the semester's breaks.
    static func items(for blocks: [Block], in interval: DateInterval, breaks: [DateInterval], math: CalendarMath) -> [CalendarItem] {
        var lookup: [String: Block] = [:]
        let snapshots = blocks.map { block in
            let key = key(for: block)
            lookup[key] = block
            return BlockSnapshot(
                id: key, start: block.start, end: block.end,
                recurrence: block.recurrence, exceptionDates: block.exceptionDates)
        }
        return RecurrenceExpander.occurrences(of: snapshots, in: interval, breaks: breaks, math: math)
            .compactMap { occurrence in lookup[occurrence.blockID].map { CalendarItem(block: $0, occurrence: occurrence) } }
    }
}

/// Whether a change to a repeating block applies to one occurrence or the whole series.
enum ChangeScope {
    case onlyThis
    case allEvents
}

/// Mutations shared by the month view, week view and editor. All go through the model context so ⌘Z works.
@MainActor
enum BlockActions {
    /// Moves/resizes an occurrence to `newStart`–`newEnd`.
    static func reschedule(_ item: CalendarItem, to newStart: Date, end newEnd: Date, scope: ChangeScope, context: ModelContext, math: CalendarMath) {
        let block = item.block
        guard item.isRecurring else {
            block.start = newStart
            block.end = newEnd
            return
        }
        switch scope {
        case .onlyThis:
            let single = detach(item, context: context, math: math)
            single.start = newStart
            single.end = newEnd
        case .allEvents:
            // Keep the series anchored on its first day; shift time of day and duration.
            let dayShift = math.calendar.dateComponents([.day], from: math.startOfDay(item.start), to: math.startOfDay(newStart)).day ?? 0
            if dayShift != 0, var rule = block.recurrence {
                rule.weekdays = Set(rule.weekdays.map { (($0 - 1 + dayShift) % 7 + 7) % 7 + 1 })
                block.recurrence = rule
            }
            let anchorDay = math.add(days: dayShift, to: math.startOfDay(block.start))
            block.start = math.date(anchorDay, keepingTimeOf: newStart)
            block.end = block.start.addingTimeInterval(newEnd.timeIntervalSince(newStart))
        }
    }

    /// Removes an occurrence (`onlyThis`) or the whole series.
    static func delete(_ item: CalendarItem, scope: ChangeScope, context: ModelContext, math: CalendarMath) {
        if item.isRecurring && scope == .onlyThis {
            item.block.exceptionDates.append(math.startOfDay(item.start))
        } else {
            context.delete(item.block)
        }
    }

    /// Turns one occurrence of a series into its own block; the series skips that day.
    @discardableResult
    static func detach(_ item: CalendarItem, context: ModelContext, math: CalendarMath) -> Block {
        let source = item.block
        source.exceptionDates.append(math.startOfDay(item.start))
        let copy = Block(title: source.title, start: item.start, end: item.end, area: source.area, location: source.location, notes: source.notes)
        context.insert(copy)
        return copy
    }
}

/// Drag payloads between calendar cells.
enum CalendarDragPayload {
    static func block(_ item: CalendarItem) -> String { "block|\(item.id)" }
    static func task(_ task: TaskItem) -> String { "task|\(CalendarFeed.key(for: task))" }
}
