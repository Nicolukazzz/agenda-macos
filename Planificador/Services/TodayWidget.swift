import AgendaCore
import Foundation
import OSLog
import SwiftData
import WidgetKit

/// Writes what the Today widget shows: the next week of classes and events, and the open tasks with a date.
@MainActor
enum TodayWidget {
    static let kind = "TodayAgenda"
    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "TodayWidget")
    /// What was last written, so saves that don't touch the calendar or the tasks cost no disk work.
    private static var written: TodaySnapshot?

    /// `~/Library/Application Support/com.nicolas.agenda/today-widget.json`, next to the store and the money snapshot.
    static var snapshotURL: URL {
        StoreLoader.storeURL.deletingLastPathComponent().appending(path: "today-widget.json")
    }

    static func snapshot(_ context: ModelContext, semester: Semester, now: Date = .now) -> TodaySnapshot {
        let math = CalendarMath()
        let start = math.startOfDay(now)
        let end = math.add(days: TodaySnapshot.horizonDays, to: start)

        // "On now / next" is about things with a time: all-day events stay out, and so do events drawn
        // by hand across the whole day (a holiday from 0:00 to 23:59), which would hide every class under them.
        let blocks = ((try? context.fetch(FetchDescriptor<Block>())) ?? [])
            .filter { !$0.isAllDay && $0.end.timeIntervalSince($0.start) < 23 * 3600 }
        let events = CalendarFeed.items(for: blocks, in: DateInterval(start: start, end: end), breaks: semester.breaks, math: math).map {
            TodaySnapshot.Event(title: $0.block.title, location: $0.block.location, colorHex: $0.colorHex,
                                start: $0.start, end: $0.end, isClass: $0.block.isClassSchedule)
        }

        let open = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let tasks = open.compactMap { task -> TodaySnapshot.Due? in
            // Same rule as the task lists: tasks of archived semesters stay out.
            if let area = task.area, area.semester?.isActive != true { return nil }
            guard let due = task.dueDate, due < end else { return nil }
            return TodaySnapshot.Due(title: task.title, colorHex: task.displayColorHex, due: due, hasTime: task.dueHasTime)
        }
        return TodaySnapshot(updatedAt: now, events: events, tasks: tasks)
    }

    /// Rewrites the widget's JSON and asks WidgetKit to redraw, only when something changed.
    static func refresh(_ context: ModelContext, semester: Semester) {
        guard !AppEnvironment.isPreview else { return }
        var current = snapshot(context, semester: semester)
        let previous = written ?? (try? TodaySnapshot.decode(Data(contentsOf: snapshotURL)))
        if let previous {
            let stamp = current.updatedAt
            current.updatedAt = previous.updatedAt
            written = previous
            guard previous != current else { return }
            current.updatedAt = stamp
        }
        do {
            try current.encoded().write(to: snapshotURL, options: .atomic)
            written = current
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        } catch {
            log.error("Today snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
