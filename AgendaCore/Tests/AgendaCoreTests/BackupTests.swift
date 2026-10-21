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
            tasks: [.init(id: "t1", title: "Taller", notes: "n", dueDate: date, dueHasTime: true, areaID: "a1", priority: 2, isDone: false, completedAt: nil, createdAt: date, subtasks: [.init(title: "Leer", isDone: true, order: 0)])])
        let decoded = try AgendaBackup.decode(try backup.encoded())
        #expect(decoded == backup)
        #expect(decoded.version == AgendaBackup.currentVersion)
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
