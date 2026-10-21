import Foundation
import Testing
@testable import AgendaCore

private let bogota: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Bogota")!
    return calendar
}()
private let math = CalendarMath(calendar: bogota)

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    bogota.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct CalendarMathTests {
    @Test func weekStartsOnMonday() {
        // 2026-10-21 is a Wednesday.
        let week = math.weekDays(containing: day(2026, 10, 21, 15))
        #expect(week.first == day(2026, 10, 19))
        #expect(week.last == day(2026, 10, 25))
    }

    @Test func sundayBelongsToPreviousWeek() {
        #expect(math.startOfWeek(containing: day(2026, 10, 25, 22)) == day(2026, 10, 19))
    }

    @Test func monthGridCoversWholeMonth() {
        let grid = math.monthGrid(containing: day(2026, 10, 5))
        #expect(grid.allSatisfy { $0.count == 7 })
        #expect(grid.first?.first == day(2026, 9, 28)) // Oct 1 2026 is a Thursday
        #expect(grid.last?.last == day(2026, 11, 1))
        #expect(grid.count == 5)
    }

    @Test func februaryStartingMondayHasFourRows() {
        // Feb 2027 starts on Monday and has 28 days.
        #expect(math.monthGrid(containing: day(2027, 2, 10)).count == 4)
    }
}

struct RecurrenceExpanderTests {
    let semesterEnd = day(2026, 12, 31)

    /// Mondays and Wednesdays 10:00–12:00 from Monday 2026-07-06.
    var classBlock: BlockSnapshot {
        BlockSnapshot(
            id: "bd", start: day(2026, 7, 6, 10), end: day(2026, 7, 6, 12),
            recurrence: WeeklyRecurrence(weekdays: [2, 4], until: semesterEnd))
    }

    @Test func expandsWeeklyDays() {
        let week = DateInterval(start: day(2026, 10, 19), end: day(2026, 10, 26))
        let result = RecurrenceExpander.occurrences(of: [classBlock], in: week, math: math)
        #expect(result.map(\.start) == [day(2026, 10, 19, 10), day(2026, 10, 21, 10)])
        #expect(result.allSatisfy { $0.end.timeIntervalSince($0.start) == 7200 && $0.isRecurring })
    }

    @Test func skipsExceptionsAndBreaks() {
        var block = classBlock
        block.exceptionDates = [day(2026, 10, 19)]
        let recess = DateInterval(start: day(2026, 10, 21), end: day(2026, 10, 22))
        let week = DateInterval(start: day(2026, 10, 19), end: day(2026, 10, 26))
        #expect(RecurrenceExpander.occurrences(of: [block], in: week, breaks: [recess], math: math).isEmpty)
    }

    @Test func stopsAtUntilDate() {
        let lateDecember = DateInterval(start: day(2026, 12, 28), end: day(2027, 1, 11))
        let result = RecurrenceExpander.occurrences(of: [classBlock], in: lateDecember, math: math)
        #expect(result.map(\.start) == [day(2026, 12, 28, 10), day(2026, 12, 30, 10)])
    }

    @Test func doesNotStartBeforeFirstOccurrence() {
        let july = DateInterval(start: day(2026, 7, 1), end: day(2026, 7, 8))
        let result = RecurrenceExpander.occurrences(of: [classBlock], in: july, math: math)
        #expect(result.map(\.start) == [day(2026, 7, 6, 10)])
    }

    @Test func singleBlocksOverlappingInterval() {
        let single = BlockSnapshot(id: "cita", start: day(2026, 10, 20, 8), end: day(2026, 10, 20, 10))
        let week = DateInterval(start: day(2026, 10, 19), end: day(2026, 10, 26))
        let result = RecurrenceExpander.occurrences(of: [single, classBlock], in: week, math: math)
        #expect(result.map(\.blockID) == ["bd", "cita", "bd"])
        #expect(result[1].isRecurring == false)
    }

    @Test func crossesMonthEnd() {
        let interval = DateInterval(start: day(2026, 10, 26), end: day(2026, 11, 9))
        #expect(RecurrenceExpander.occurrences(of: [classBlock], in: interval, math: math).count == 4)
    }
}

struct OverlapLayoutTests {
    @Test func separateEventsUseFullWidth() {
        let slots = OverlapLayout.slots(for: [(day(2026, 1, 1, 8), day(2026, 1, 1, 9)), (day(2026, 1, 1, 9), day(2026, 1, 1, 10))])
        #expect(slots.map(\.columnCount) == [1, 1])
    }

    @Test func overlappingEventsSplit() {
        let slots = OverlapLayout.slots(for: [
            (day(2026, 1, 1, 8), day(2026, 1, 1, 10)),
            (day(2026, 1, 1, 9), day(2026, 1, 1, 11)),
            (day(2026, 1, 1, 10), day(2026, 1, 1, 12)),
        ])
        #expect(slots.map(\.column) == [0, 1, 0])
        #expect(slots.map(\.columnCount) == [2, 2, 2])
    }
}

struct TagCompletionTests {
    let candidates = [
        TagCandidate(tag: "bd", name: "BD"),
        TagCandidate(tag: "so", name: "Sistemas Operativos"),
        TagCandidate(tag: "si", name: "Sistemas de la Informacion"),
        TagCandidate(tag: "gti", name: "Gestión TI"),
    ]

    @Test func detectsQueryAtEnd() {
        #expect(TagCompletion.currentQuery(in: "Estudiar #b") == "b")
        #expect(TagCompletion.currentQuery(in: "#") == "")
        #expect(TagCompletion.currentQuery(in: "Estudiar #bd parcial") == nil)
        #expect(TagCompletion.currentQuery(in: "correo@#x") == nil)
        #expect(TagCompletion.currentQuery(in: "Sin tag") == nil)
    }

    @Test func ranksTagPrefixBeforeNameWords() {
        #expect(TagCompletion.suggestions(for: "s", in: candidates).map(\.tag) == ["so", "si"])
        #expect(TagCompletion.suggestions(for: "oper", in: candidates).map(\.tag) == ["so"])
        #expect(TagCompletion.suggestions(for: "gestion", in: candidates).map(\.tag) == ["gti"])
        #expect(TagCompletion.suggestions(for: "", in: candidates).count == 4)
    }

    @Test func completesReplacingPartialTag() {
        #expect(TagCompletion.complete("Estudiar #b", with: "bd") == "Estudiar #bd ")
        #expect(TagCompletion.complete("Estudiar", with: "bd") == "Estudiar #bd ")
    }

    @Test func extractsKnownTagAndKeepsUnknown() {
        let result = TagCompletion.extract(from: "Estudiar #BD parcial #raro", known: ["bd", "so"])
        #expect(result.title == "Estudiar parcial #raro")
        #expect(result.tag == "bd")
    }
}
