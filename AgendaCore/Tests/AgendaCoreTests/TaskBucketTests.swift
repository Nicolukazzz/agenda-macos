import Foundation
import Testing
@testable import AgendaCore

struct TaskBucketTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }()
    var math: CalendarMath { CalendarMath(calendar: calendar) }
    func d(_ day: Int, _ h: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))! }

    /// Now: Wednesday Oct 21, 16:00.
    var now: Date { d(21, 16) }

    @Test func buckets() {
        #expect(TaskBucket.bucket(due: nil, hasTime: false, now: now, math: math) == .someday)
        #expect(TaskBucket.bucket(due: d(20), hasTime: false, now: now, math: math) == .overdue)
        #expect(TaskBucket.bucket(due: d(21), hasTime: false, now: now, math: math) == .today)
        #expect(TaskBucket.bucket(due: d(21, 10), hasTime: true, now: now, math: math) == .overdue)
        #expect(TaskBucket.bucket(due: d(21, 18), hasTime: true, now: now, math: math) == .today)
        #expect(TaskBucket.bucket(due: d(22), hasTime: false, now: now, math: math) == .tomorrow)
        #expect(TaskBucket.bucket(due: d(25), hasTime: false, now: now, math: math) == .thisWeek)
        #expect(TaskBucket.bucket(due: d(26), hasTime: false, now: now, math: math) == .later)
    }
}
