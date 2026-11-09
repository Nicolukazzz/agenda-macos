import Foundation

/// Plain, versioned snapshot of everything in the database (notes are files and aren't included).
/// Relationships use string ids so the file is readable and stable.
public struct AgendaBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct SemesterRecord: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var folderPath: String
        public var startDate: Date
        public var endDate: Date
        public var breaks: [DateInterval]
        public var isActive: Bool
        public init(id: String, name: String, folderPath: String, startDate: Date, endDate: Date, breaks: [DateInterval], isActive: Bool) {
            self.id = id; self.name = name; self.folderPath = folderPath; self.startDate = startDate; self.endDate = endDate; self.breaks = breaks; self.isActive = isActive
        }
    }

    public struct AreaRecord: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var tag: String
        public var colorHex: String
        public var folderPath: String?
        public var semesterID: String?
        public var isArchived: Bool
        public var sortOrder: Int
        public init(id: String, name: String, tag: String, colorHex: String, folderPath: String?, semesterID: String?, isArchived: Bool, sortOrder: Int) {
            self.id = id; self.name = name; self.tag = tag; self.colorHex = colorHex; self.folderPath = folderPath; self.semesterID = semesterID; self.isArchived = isArchived; self.sortOrder = sortOrder
        }
    }

    public struct BlockRecord: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var notes: String
        public var location: String
        public var areaID: String?
        public var recurrence: WeeklyRecurrence?
        public var exceptionDates: [Date]
        public var taskID: String?
        public init(id: String, title: String, start: Date, end: Date, notes: String, location: String, areaID: String?, recurrence: WeeklyRecurrence?, exceptionDates: [Date], taskID: String?) {
            self.id = id; self.title = title; self.start = start; self.end = end; self.notes = notes; self.location = location; self.areaID = areaID; self.recurrence = recurrence; self.exceptionDates = exceptionDates; self.taskID = taskID
        }
    }

    public struct SubtaskRecord: Codable, Equatable, Sendable {
        public var title: String
        public var isDone: Bool
        public var order: Int
        public init(title: String, isDone: Bool, order: Int) { self.title = title; self.isDone = isDone; self.order = order }
    }

    public struct TaskRecord: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var notes: String
        public var dueDate: Date?
        public var dueHasTime: Bool
        public var areaID: String?
        public var priority: Int
        public var isDone: Bool
        public var completedAt: Date?
        public var createdAt: Date
        public var subtasks: [SubtaskRecord]
        /// Reminders link. Optional so backups written before the Reminders sync still decode.
        public var createsReminder: Bool?
        public var reminderID: String?
        public var reminderExternalID: String?
        public var reminderListID: String?
        public var reminderSnapshot: ReminderFields?
        public init(id: String, title: String, notes: String, dueDate: Date?, dueHasTime: Bool, areaID: String?, priority: Int, isDone: Bool, completedAt: Date?, createdAt: Date, subtasks: [SubtaskRecord],
                    createsReminder: Bool? = nil, reminderID: String? = nil, reminderExternalID: String? = nil, reminderListID: String? = nil, reminderSnapshot: ReminderFields? = nil) {
            self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate; self.dueHasTime = dueHasTime; self.areaID = areaID; self.priority = priority; self.isDone = isDone; self.completedAt = completedAt; self.createdAt = createdAt; self.subtasks = subtasks
            self.createsReminder = createsReminder; self.reminderID = reminderID; self.reminderExternalID = reminderExternalID; self.reminderListID = reminderListID; self.reminderSnapshot = reminderSnapshot
        }
    }

    public struct MoneyCategoryRecord: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var tag: String
        public var emoji: String
        public var colorHex: String
        public var kind: MoneyKind
        public var sortOrder: Int
        public var isArchived: Bool
        public init(id: String, name: String, tag: String, emoji: String, colorHex: String, kind: MoneyKind, sortOrder: Int, isArchived: Bool) {
            self.id = id; self.name = name; self.tag = tag; self.emoji = emoji; self.colorHex = colorHex; self.kind = kind; self.sortOrder = sortOrder; self.isArchived = isArchived
        }
    }

    public struct MoneyEntryRecord: Codable, Equatable, Sendable {
        public var title: String
        public var kind: MoneyKind
        public var amount: Decimal
        public var currency: Currency
        public var copPerUSD: Decimal
        public var date: Date
        public var createdAt: Date
        public var categoryID: String?
        public var recurringID: String?
        public init(title: String, kind: MoneyKind, amount: Decimal, currency: Currency, copPerUSD: Decimal, date: Date, createdAt: Date, categoryID: String?, recurringID: String? = nil) {
            self.title = title; self.kind = kind; self.amount = amount; self.currency = currency; self.copPerUSD = copPerUSD; self.date = date; self.createdAt = createdAt; self.categoryID = categoryID
            self.recurringID = recurringID
        }
    }

    public struct RecurringRecord: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var kind: MoneyKind
        public var amount: Decimal
        public var currency: Currency
        public var cadence: Cadence
        public var start: Date
        public var lastCharged: Date?
        public var isActive: Bool
        public var categoryID: String?
        public init(id: String, title: String, kind: MoneyKind, amount: Decimal, currency: Currency, cadence: Cadence, start: Date, lastCharged: Date?, isActive: Bool, categoryID: String?) {
            self.id = id; self.title = title; self.kind = kind; self.amount = amount; self.currency = currency; self.cadence = cadence
            self.start = start; self.lastCharged = lastCharged; self.isActive = isActive; self.categoryID = categoryID
        }
    }

    public var version: Int
    public var exportedAt: Date
    public var semesters: [SemesterRecord]
    public var areas: [AreaRecord]
    public var blocks: [BlockRecord]
    public var tasks: [TaskRecord]
    /// Money. Nil in backups written before it existed; restoring those leaves money untouched.
    public var moneyCategories: [MoneyCategoryRecord]?
    public var moneyEntries: [MoneyEntryRecord]?
    public var recurring: [RecurringRecord]?

    public init(exportedAt: Date, semesters: [SemesterRecord], areas: [AreaRecord], blocks: [BlockRecord], tasks: [TaskRecord],
                moneyCategories: [MoneyCategoryRecord]? = nil, moneyEntries: [MoneyEntryRecord]? = nil, recurring: [RecurringRecord]? = nil) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.semesters = semesters
        self.areas = areas
        self.blocks = blocks
        self.tasks = tasks
        self.moneyCategories = moneyCategories
        self.moneyEntries = moneyEntries
        self.recurring = recurring
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> AgendaBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgendaBackup.self, from: data)
    }
}

/// Daily backup files: `agenda-AAAA-MM-DD.json`, keeping the newest `keep`.
public enum BackupRotation {
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "agenda-%04d-%02d-%02d.json", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// Names to delete so only the newest `keep` backups remain. Ignores files that aren't backups.
    public static func expired(_ names: [String], keep: Int = 14) -> [String] {
        let backups = names.filter { $0.wholeMatch(of: /agenda-\d{4}-\d{2}-\d{2}\.json/) != nil }.sorted(by: >)
        return Array(backups.dropFirst(keep))
    }
}
