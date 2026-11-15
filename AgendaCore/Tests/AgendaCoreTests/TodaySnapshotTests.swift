import Foundation
import Testing
@testable import AgendaCore

struct TodaySnapshotTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }()
    func d(_ day: Int, _ h: Int = 0, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
    func event(_ title: String, _ start: Date, hours: Double = 2) -> TodaySnapshot.Event {
        .init(title: title, location: "", colorHex: "#000000", start: start, end: start.addingTimeInterval(hours * 3600), isClass: true)
    }

    var snapshot: TodaySnapshot {
        TodaySnapshot(
            updatedAt: d(16, 6),
            events: [event("SO", d(16, 14)), event("BD", d(16, 9)), event("TC", d(17, 7))],
            tasks: [
                .init(title: "Taller", colorHex: "#000000", due: d(16, 23, 59), hasTime: false),
                .init(title: "Quiz", colorHex: "#000000", due: d(15, 23, 59), hasTime: false),
                .init(title: "Entrega", colorHex: "#000000", due: d(16, 18), hasTime: true),
                .init(title: "Parcial", colorHex: "#000000", due: d(20, 23, 59), hasTime: false),
            ])
    }

    @Test func sortsOnInit() {
        #expect(snapshot.events.map(\.title) == ["BD", "SO", "TC"])
        #expect(snapshot.tasks.map(\.title) == ["Quiz", "Entrega", "Taller", "Parcial"])
    }

    @Test func currentAndNext() {
        #expect(snapshot.current(at: d(16, 8)) == nil)
        #expect(snapshot.next(after: d(16, 8))?.title == "BD")
        #expect(snapshot.current(at: d(16, 10))?.title == "BD")
        #expect(snapshot.next(after: d(16, 10))?.title == "SO")
        // An event ends exactly at 11:00: it is no longer current then.
        #expect(snapshot.current(at: d(16, 11)) == nil)
        #expect(snapshot.upcomingToday(at: d(16, 10), calendar: calendar).map(\.title) == ["SO"])
        #expect(snapshot.upcomingToday(at: d(16, 17), calendar: calendar).isEmpty)
        #expect(snapshot.next(after: d(16, 17))?.title == "TC")
        #expect(snapshot.next(after: d(18)) == nil)
    }

    @Test func dueTodayIncludesOverdueButNotLater() {
        #expect(snapshot.dueToday(at: d(16, 10), calendar: calendar).map(\.title) == ["Quiz", "Entrega", "Taller"])
    }

    @Test func overdueRules() {
        let tasks = snapshot.tasks
        let now = d(16, 19)
        #expect(snapshot.isOverdue(tasks[0], at: now, calendar: calendar))        // yesterday, no time
        #expect(snapshot.isOverdue(tasks[1], at: now, calendar: calendar))        // today 18:00, passed
        #expect(!snapshot.isOverdue(tasks[1], at: d(16, 17), calendar: calendar)) // today 18:00, still ahead
        #expect(!snapshot.isOverdue(tasks[2], at: now, calendar: calendar))       // today, no time
    }

    @Test func refreshDatesAreFutureSortedAndUnique() {
        let dates = snapshot.refreshDates(after: d(16, 10), calendar: calendar)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.allSatisfy { $0 > d(16, 10) })
        #expect(dates.first == d(16, 11))          // BD ends
        #expect(dates.contains(d(16, 18)))         // timed task passes
        #expect(dates.contains(d(17)))             // midnight
        #expect(!dates.contains(d(16, 23, 59)))    // untimed tasks don't force a redraw
    }

    @Test func survivesJSON() throws {
        #expect(try TodaySnapshot.decode(snapshot.encoded()) == snapshot)
    }
}
