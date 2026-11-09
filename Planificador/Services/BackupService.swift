import AgendaCore
import Foundation
import OSLog
import SwiftData

/// Exports the database to JSON and restores it. Daily automatic backups go to
/// `~/Documents/PUJ/.respaldos/` (next to the classes folder), keeping the newest 14.
@MainActor
enum BackupService {
    private static let log = Logger(subsystem: "com.nicolas.agenda", category: "Backup")

    /// `<parent of classes root>/.respaldos`, e.g. `~/Documents/PUJ/.respaldos`.
    static func folder(classesRoot: URL) -> URL {
        classesRoot.deletingLastPathComponent().appending(path: ".respaldos", directoryHint: .isDirectory)
    }

    // MARK: Export

    static func snapshot(_ context: ModelContext) throws -> AgendaBackup {
        func key(_ object: AnyObject) -> String { CalendarFeed.key(for: object) }
        let semesters = try context.fetch(FetchDescriptor<Semester>())
        let areas = try context.fetch(FetchDescriptor<Area>())
        let blocks = try context.fetch(FetchDescriptor<Block>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let categories = try context.fetch(FetchDescriptor<MoneyCategory>())
        let entries = try context.fetch(FetchDescriptor<MoneyEntry>())
        let recurring = try context.fetch(FetchDescriptor<RecurringMoney>())
        return AgendaBackup(
            exportedAt: .now,
            semesters: semesters.map {
                .init(id: key($0), name: $0.name, folderPath: $0.folderPath, startDate: $0.startDate, endDate: $0.endDate, breaks: $0.breaks, isActive: $0.isActive)
            },
            areas: areas.map {
                .init(id: key($0), name: $0.name, tag: $0.tag, colorHex: $0.colorHex, folderPath: $0.folderPath,
                      semesterID: $0.semester.map(key), isArchived: $0.isArchived, sortOrder: $0.sortOrder)
            },
            blocks: blocks.map {
                .init(id: key($0), title: $0.title, start: $0.start, end: $0.end, notes: $0.notes, location: $0.location,
                      areaID: $0.area.map(key), recurrence: $0.recurrence, exceptionDates: $0.exceptionDates, taskID: $0.linkedTask.map(key))
            },
            tasks: tasks.map {
                .init(id: key($0), title: $0.title, notes: $0.notes, dueDate: $0.dueDate, dueHasTime: $0.dueHasTime, areaID: $0.area.map(key),
                      priority: $0.priority, isDone: $0.isDone, completedAt: $0.completedAt, createdAt: $0.createdAt,
                      subtasks: $0.subtasks.sorted { $0.order < $1.order }.map { .init(title: $0.title, isDone: $0.isDone, order: $0.order) },
                      createsReminder: $0.createsReminder, reminderID: $0.reminderID, reminderExternalID: $0.reminderExternalID,
                      reminderListID: $0.reminderListID, reminderSnapshot: $0.reminderFieldsSnapshot)
            },
            moneyCategories: categories.map {
                .init(id: key($0), name: $0.name, tag: $0.tag, emoji: $0.emoji, colorHex: $0.colorHex, kind: $0.kind, sortOrder: $0.sortOrder, isArchived: $0.isArchived)
            },
            moneyEntries: entries.map {
                .init(title: $0.title, kind: $0.kind, amount: $0.amount, currency: $0.currency, copPerUSD: $0.copPerUSD,
                      date: $0.date, createdAt: $0.createdAt, categoryID: $0.category.map(key), recurringID: $0.recurring.map(key))
            },
            recurring: recurring.map {
                .init(id: key($0), title: $0.title, kind: $0.kind, amount: $0.amount, currency: $0.currency, cadence: $0.cadence, every: $0.every,
                      start: $0.start, lastCharged: $0.lastCharged, isActive: $0.isActive, categoryID: $0.category.map(key))
            })
    }

    static func export(_ context: ModelContext, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try snapshot(context).encoded().write(to: url, options: .atomic)
    }

    /// Writes today's backup once per day and prunes old ones. Never throws into the UI.
    static func runDailyBackup(_ context: ModelContext, classesRoot: URL) {
        guard !AppEnvironment.isPreview else { return }
        let folder = folder(classesRoot: classesRoot)
        let target = folder.appending(path: BackupRotation.fileName(for: .now))
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        do {
            // Don't create an empty backup before the first semester exists.
            guard try context.fetchCount(FetchDescriptor<Semester>()) > 0 else { return }
            try export(context, to: target)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            for name in BackupRotation.expired(names) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
            log.info("Daily backup written: \(target.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Daily backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func latestBackup(classesRoot: URL) -> URL? {
        let folder = folder(classesRoot: classesRoot)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("agenda-") && $0.hasSuffix(".json") }.max().map { folder.appending(path: $0) }
    }

    // MARK: Restore

    /// Replaces everything in the database with the backup's contents.
    /// Money is replaced only when the backup has it, so an older backup can't wipe it.
    static func restore(_ backup: AgendaBackup, into context: ModelContext) throws {
        if let categoryRecords = backup.moneyCategories {
            try context.delete(model: MoneyEntry.self)
            try context.delete(model: RecurringMoney.self)
            try context.delete(model: MoneyCategory.self)
            var categories: [String: MoneyCategory] = [:]
            for record in categoryRecords {
                let category = MoneyCategory(name: record.name, emoji: record.emoji, colorHex: record.colorHex, kind: record.kind, sortOrder: record.sortOrder)
                category.tag = record.tag
                category.isArchived = record.isArchived
                context.insert(category)
                categories[record.id] = category
            }
            var recurring: [String: RecurringMoney] = [:]
            for record in backup.recurring ?? [] {
                let item = RecurringMoney(title: record.title, kind: record.kind, amount: record.amount, currency: record.currency,
                                          cadence: record.cadence, start: record.start, category: record.categoryID.flatMap { categories[$0] })
                item.every = record.every ?? 1
                item.lastCharged = record.lastCharged
                item.isActive = record.isActive
                context.insert(item)
                recurring[record.id] = item
            }
            for record in backup.moneyEntries ?? [] {
                let entry = MoneyEntry(title: record.title, kind: record.kind, amount: record.amount, currency: record.currency,
                                       copPerUSD: record.copPerUSD, date: record.date, category: record.categoryID.flatMap { categories[$0] })
                entry.createdAt = record.createdAt
                entry.recurring = record.recurringID.flatMap { recurring[$0] }
                context.insert(entry)
            }
        }

        try context.delete(model: Subtask.self)
        try context.delete(model: Block.self)
        try context.delete(model: TaskItem.self)
        try context.delete(model: Area.self)
        try context.delete(model: Semester.self)

        var semesters: [String: Semester] = [:]
        for record in backup.semesters {
            let semester = Semester(name: record.name, folderPath: record.folderPath, startDate: record.startDate, endDate: record.endDate, breaks: record.breaks, isActive: record.isActive)
            context.insert(semester)
            semesters[record.id] = semester
        }
        var areas: [String: Area] = [:]
        for record in backup.areas {
            let area = Area(name: record.name, tag: record.tag, colorHex: record.colorHex, folderPath: record.folderPath,
                            semester: record.semesterID.flatMap { semesters[$0] }, sortOrder: record.sortOrder)
            area.isArchived = record.isArchived
            context.insert(area)
            areas[record.id] = area
        }
        var tasks: [String: TaskItem] = [:]
        for record in backup.tasks {
            let task = TaskItem(title: record.title, dueDate: record.dueDate, dueHasTime: record.dueHasTime,
                                area: record.areaID.flatMap { areas[$0] }, priority: record.priority, notes: record.notes)
            task.isDone = record.isDone
            task.completedAt = record.completedAt
            task.createdAt = record.createdAt
            task.createsReminder = record.createsReminder ?? false
            task.reminderID = record.reminderID
            task.reminderExternalID = record.reminderExternalID
            task.reminderListID = record.reminderListID
            task.reminderFieldsSnapshot = record.reminderSnapshot
            context.insert(task)
            for sub in record.subtasks {
                let subtask = Subtask(title: sub.title, order: sub.order)
                subtask.isDone = sub.isDone
                task.subtasks.append(subtask)
            }
            tasks[record.id] = task
        }
        for record in backup.blocks {
            let block = Block(title: record.title, start: record.start, end: record.end, area: record.areaID.flatMap { areas[$0] },
                              recurrence: record.recurrence, location: record.location, notes: record.notes)
            block.exceptionDates = record.exceptionDates
            block.linkedTask = record.taskID.flatMap { tasks[$0] }
            context.insert(block)
        }
        try context.save()
    }
}
