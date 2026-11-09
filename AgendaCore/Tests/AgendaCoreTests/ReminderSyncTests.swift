import Foundation
import Testing
@testable import AgendaCore

struct ReminderSyncTests {
    private func fields(title: String = "Buy milk", notes: String = "", due: ReminderDue? = nil, isDone: Bool = false, priority: Int = 0) -> ReminderFields {
        ReminderFields(title: title, notes: notes, due: due, isDone: isDone, priority: priority)
    }

    @Test func firstLinkPushesApp() {
        let app = fields(title: "Buy milk")
        let result = ReminderMerge.merge(app: app, remote: fields(title: ""), base: nil)
        #expect(result.fields == app)
        #expect(!result.updatesApp)
        #expect(result.updatesRemote)
    }

    @Test func completedOnPhonePullsIntoApp() {
        let base = fields()
        let result = ReminderMerge.merge(app: base, remote: fields(isDone: true), base: base)
        #expect(result.fields.isDone)
        #expect(result.updatesApp)
        #expect(!result.updatesRemote)
    }

    @Test func editsOnBothSidesMergePerField() {
        let base = fields()
        let result = ReminderMerge.merge(app: fields(title: "Buy oat milk"), remote: fields(isDone: true), base: base)
        #expect(result.fields == fields(title: "Buy oat milk", isDone: true))
        #expect(result.updatesApp)
        #expect(result.updatesRemote)
    }

    @Test func appWinsSameFieldConflict() {
        let base = fields()
        let result = ReminderMerge.merge(app: fields(title: "App"), remote: fields(title: "Phone"), base: base)
        #expect(result.fields.title == "App")
    }

    @Test func nothingChangedIsNoOp() {
        let base = fields(notes: "n", priority: 1)
        let result = ReminderMerge.merge(app: base, remote: base, base: base)
        #expect(!result.updatesApp)
        #expect(!result.updatesRemote)
    }

    @Test func allDayDueKeepsOnlyTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 59)))
        let due = ReminderDue(date: date, hasTime: false, calendar: calendar)
        #expect(due == ReminderDue(year: 2026, month: 11, day: 14))
        #expect(!due.hasTime)
        #expect(due.components.hour == nil)
        #expect(due.appDate(calendar: calendar) == date)
    }

    @Test func timedDueRoundTrips() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 18, minute: 30)))
        let due = ReminderDue(date: date, hasTime: true, calendar: calendar)
        #expect(due.hasTime)
        #expect(ReminderDue(components: due.components) == due)
        #expect(due.appDate(calendar: calendar) == date)
    }

    @Test func phoneDateWithoutTimeIsAllDay() {
        let due = ReminderDue(components: DateComponents(year: 2026, month: 12, day: 24))
        #expect(due == ReminderDue(year: 2026, month: 12, day: 24))
        #expect(ReminderDue(components: DateComponents(hour: 9)) == nil)
    }

    @Test func priorityRoundTrips() {
        for priority in 0...2 {
            #expect(ReminderPriority.app(fromEventKit: ReminderPriority.eventKit(fromApp: priority)) == priority)
        }
        #expect(ReminderPriority.app(fromEventKit: 9) == 1)
    }

    @Test func removedListIsCapped() {
        var removed = RemovedReminders(limit: 3)
        for id in ["a", "b", "c", "d", "b"] { removed.insert(id) }
        #expect(removed.ids == ["c", "d", "b"])
    }

    @Test func deletionGuardBlocksMassDeletes() {
        #expect(ReminderDeletionGuard.allows(deleting: 1, ofLinked: 1))
        #expect(ReminderDeletionGuard.allows(deleting: 5, ofLinked: 10))
        #expect(!ReminderDeletionGuard.allows(deleting: 8, ofLinked: 10))
    }

    @Test func oldBackupsWithoutReminderFieldsDecode() throws {
        let json = """
        {"version":1,"exportedAt":"2026-11-08T12:00:00Z","semesters":[],"areas":[],"blocks":[],
         "tasks":[{"id":"t1","title":"Old","notes":"","dueHasTime":false,"priority":0,"isDone":false,"createdAt":"2026-11-08T12:00:00Z","subtasks":[]}]}
        """
        let backup = try AgendaBackup.decode(Data(json.utf8))
        #expect(backup.tasks.first?.createsReminder == nil)
        #expect(backup.tasks.first?.reminderID == nil)
    }
}
