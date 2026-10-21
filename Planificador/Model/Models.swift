import AgendaCore
import Foundation
import SwiftData

/// A university term, e.g. `2026-2`, mapped to its folder under the classes root.
@Model
final class Semester {
    var name: String
    var folderPath: String
    var startDate: Date
    var endDate: Date
    /// Recess weeks and holidays: class blocks are skipped inside these ranges.
    var breaks: [DateInterval]
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Area.semester)
    var areas: [Area] = []

    init(name: String, folderPath: String, startDate: Date, endDate: Date, breaks: [DateInterval] = [], isActive: Bool = true) {
        self.name = name
        self.folderPath = folderPath
        self.startDate = startDate
        self.endDate = endDate
        self.breaks = breaks
        self.isActive = isActive
        self.createdAt = .now
    }

    /// Keeps the dates on the term's half of the year (`AAAA-1` Jan–Jun, `AAAA-2` Jul–Dec).
    /// Also fixes semesters created by the first build, which asked for exact class dates.
    func normalizeDates() {
        guard let range = SemesterDates.range(for: name) else { return }
        if startDate != range.start { startDate = range.start }
        if endDate != range.end { endDate = range.end }
    }

    var sortedAreas: [Area] {
        areas.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// A course with its folder, or a personal area (`#personal`) with no folder.
@Model
final class Area {
    var name: String
    var tag: String
    var colorHex: String
    /// Absolute path to the course folder; nil for personal areas.
    var folderPath: String?
    var semester: Semester?
    var isArchived: Bool
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \Block.area)
    var blocks: [Block] = []

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.area)
    var tasks: [TaskItem] = []

    init(name: String, tag: String, colorHex: String, folderPath: String?, semester: Semester?, sortOrder: Int) {
        self.name = name
        self.tag = tag
        self.colorHex = colorHex
        self.folderPath = folderPath
        self.semester = semester
        self.isArchived = false
        self.sortOrder = sortOrder
    }

    var folderURL: URL? {
        folderPath.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// True when the area should have a folder but it was renamed or moved away.
    var isFolderMissing: Bool {
        guard let folderPath else { return false }
        var isDirectory: ObjCBool = false
        return !FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory) || !isDirectory.boolValue
    }
}

/// A time block in the week calendar: a class, an appointment or scheduled work on a task.
@Model
final class Block {
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var location: String
    var area: Area?
    var recurrence: WeeklyRecurrence?
    /// Start-of-day dates where a recurring block does not happen (cancelled or moved "only this time").
    var exceptionDates: [Date]
    var linkedTask: TaskItem?

    /// Part of the class timetable (a course's weekly slot from the Schedule tab or an import).
    /// The month view hides these; it shows only what the user creates (tasks and one-off events).
    var isClassSchedule: Bool {
        recurrence != nil && area?.folderPath != nil
    }

    init(title: String, start: Date, end: Date, area: Area? = nil, recurrence: WeeklyRecurrence? = nil, location: String = "", notes: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
        self.area = area
        self.recurrence = recurrence
        self.exceptionDates = []
    }
}

@Model
final class TaskItem {
    var title: String
    var notes: String
    var dueDate: Date?
    /// When false the task is due at the end of `dueDate`'s day.
    var dueHasTime: Bool
    var area: Area?
    /// 0 normal, 1 high, 2 urgent.
    var priority: Int
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
    var subtasks: [Subtask] = []

    @Relationship(deleteRule: .nullify, inverse: \Block.linkedTask)
    var scheduledBlocks: [Block] = []

    init(title: String, dueDate: Date? = nil, dueHasTime: Bool = false, area: Area? = nil, priority: Int = 0, notes: String = "") {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.area = area
        self.priority = priority
        self.isDone = false
        self.createdAt = .now
    }
}

@Model
final class Subtask {
    var title: String
    var isDone: Bool
    var order: Int
    var task: TaskItem?

    init(title: String, order: Int) {
        self.title = title
        self.isDone = false
        self.order = order
    }
}

enum AgendaSchema {
    static let models: [any PersistentModel.Type] = [Semester.self, Area.self, Block.self, TaskItem.self, Subtask.self]
}

extension PersistentModel {
    /// Stable identity for SwiftUI lists while the object is alive. `persistentModelID` can repeat
    /// for objects that haven't been saved yet, which breaks `ForEach` diffing.
    var liveID: ObjectIdentifier { ObjectIdentifier(self) }
}
