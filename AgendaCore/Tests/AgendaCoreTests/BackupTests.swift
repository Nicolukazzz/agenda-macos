import Foundation
import Testing
@testable import AgendaCore

struct BackupTests {
    @Test func roundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000) // whole seconds survive ISO 8601
        let backup = AgendaBackup(
            exportedAt: date,
            semesters: [.init(id: "s1", name: "2026-2", folderPath: "/x/2026-2", startDate: date, endDate: date.addingTimeInterval(86_400), breaks: [DateInterval(start: date, duration: 3600)], isActive: true)],
            areas: [.init(id: "a1", name: "BD", tag: "bd", colorHex: "#4F7BF7", folderPath: "/x/2026-2/BD", semesterID: "s1", isArchived: false, sortOrder: 0)],
            blocks: [.init(id: "b1", title: "BD", start: date, end: date.addingTimeInterval(7200), notes: "", location: "12-807", areaID: "a1", recurrence: WeeklyRecurrence(weekdays: [3, 5], until: date), exceptionDates: [date], taskID: "t1")],
            tasks: [.init(id: "t1", title: "Taller", notes: "n", dueDate: date, dueHasTime: true, areaID: "a1", priority: 2, isDone: false, completedAt: nil, createdAt: date, subtasks: [.init(title: "Leer", isDone: true, order: 0)])],
            moneyCategories: [.init(id: "c1", name: "Suscripciones", tag: "suscripciones", emoji: "🔁", colorHex: "#8E6CF0", kind: .expense, sortOrder: 0, isArchived: false)],
            moneyEntries: [.init(title: "Netflix", kind: .expense, amount: Decimal(string: "3.99")!, currency: .usd, copPerUSD: Decimal(string: "4012.35")!, date: date, createdAt: date, categoryID: "c1", recurringID: "r1"),
                           .init(title: "Sueldo", kind: .income, amount: 1_500_000, currency: .cop, copPerUSD: 4_000, date: date, createdAt: date, categoryID: nil)],
            recurring: [.init(id: "r1", title: "Netflix", kind: .expense, amount: Decimal(string: "3.99")!, currency: .usd, cadence: .monthly, start: date, lastCharged: date, isActive: true, categoryID: "c1")])
        let decoded = try AgendaBackup.decode(try backup.encoded())
        #expect(decoded == backup)
        #expect(decoded.version == AgendaBackup.currentVersion)
    }

    @Test func backupWithoutMoneyStillDecodes() throws {
        let json = #"{"version":1,"exportedAt":"2026-10-21T00:00:00Z","semesters":[],"areas":[],"blocks":[],"tasks":[]}"#
        let decoded = try AgendaBackup.decode(Data(json.utf8))
        #expect(decoded.moneyCategories == nil)
        #expect(decoded.moneyEntries == nil)
    }

    @Test func rotationKeepsNewest() {
        let names = (1...16).map { String(format: "agenda-2026-10-%02d.json", $0) } + ["notes.txt"]
        let expired = BackupRotation.expired(names, keep: 14)
        #expect(expired == ["agenda-2026-10-02.json", "agenda-2026-10-01.json"])
    }

    @Test func fileNameUsesDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 22))!
        #expect(BackupRotation.fileName(for: date, calendar: calendar) == "agenda-2026-10-21.json")
    }
}
