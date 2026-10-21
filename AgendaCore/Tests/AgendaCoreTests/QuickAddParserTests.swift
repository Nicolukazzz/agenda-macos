import Foundation
import Testing
@testable import AgendaCore

private let bogota: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Bogota")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    bogota.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// "Now" is Wednesday 2026-10-21 at 16:00.
private let parser = QuickAddParser(math: CalendarMath(calendar: bogota), now: day(2026, 10, 21, 16))
private let tags: Set<String> = ["bd", "so", "gti", "tc"]

struct QuickAddParserTests {
    @Test func plainTitle() {
        #expect(parser.parse("Read chapter 4", knownTags: tags) == QuickAddResult(title: "Read chapter 4"))
    }

    @Test func tagAndWeekday() {
        let r = parser.parse("Lab report #so friday", knownTags: tags)
        #expect(r.title == "Lab report")
        #expect(r.tag == "so")
        #expect(r.dueDate == day(2026, 10, 23))
        #expect(r.hasTime == false)
    }

    @Test func spanishWeekdayWithAccent() {
        let r = parser.parse("Taller #so viernes", knownTags: tags)
        #expect(r.title == "Taller")
        #expect(r.dueDate == day(2026, 10, 23))
        #expect(parser.parse("Parcial miércoles", knownTags: tags).dueDate == day(2026, 10, 21))
    }

    @Test func todayCountsForSameWeekday() {
        #expect(parser.parse("Quiz wednesday", knownTags: tags).dueDate == day(2026, 10, 21))
    }

    @Test(arguments: ["next wednesday", "el otro miércoles", "próximo miércoles", "proximo miercoles"])
    func followingWeek(text: String) {
        let r = parser.parse("Present \(text)", knownTags: tags)
        #expect(r.dueDate == day(2026, 10, 28))
        #expect(r.title == "Present")
    }

    @Test(arguments: [("today", 21), ("hoy", 21), ("tomorrow", 22), ("mañana", 22), ("pasado mañana", 23)])
    func relativeDays(text: String, expected: Int) {
        #expect(parser.parse("Do it \(text)", knownTags: tags).dueDate == day(2026, 10, expected))
    }

    @Test func inDaysAndWeeks() {
        #expect(parser.parse("Essay in 3 days", knownTags: tags).dueDate == day(2026, 10, 24))
        #expect(parser.parse("Ensayo en 2 semanas", knownTags: tags).dueDate == day(2026, 11, 4))
        #expect(parser.parse("Ensayo en 2 semanas", knownTags: tags).title == "Ensayo")
    }

    @Test func slashDates() {
        #expect(parser.parse("Project 21/11", knownTags: tags).dueDate == day(2026, 11, 21))
        #expect(parser.parse("Project 5/2/2027", knownTags: tags).dueDate == day(2027, 2, 5))
        // Already past this year → next year.
        #expect(parser.parse("Retake 3/02", knownTags: tags).dueDate == day(2027, 2, 3))
    }

    @Test func invalidDateStaysInTitle() {
        let r = parser.parse("Exam 31/02", knownTags: tags)
        #expect(r.dueDate == nil)
        #expect(r.title == "Exam 31/02")
    }

    @Test func monthNames() {
        #expect(parser.parse("Pitch 21 nov", knownTags: tags).dueDate == day(2026, 11, 21))
        #expect(parser.parse("Pitch nov 21", knownTags: tags).dueDate == day(2026, 11, 21))
        #expect(parser.parse("Entrega 3 de diciembre", knownTags: tags).title == "Entrega 3 de diciembre") // "de" breaks the pattern: kept as text
    }

    @Test func timesSetHasTime() {
        let r = parser.parse("Submit #bd friday 6pm", knownTags: tags)
        #expect(r.dueDate == day(2026, 10, 23, 18))
        #expect(r.hasTime)
        #expect(r.title == "Submit")
        #expect(parser.parse("Call friday 18:30", knownTags: tags).dueDate == day(2026, 10, 23, 18, 30))
        #expect(parser.parse("Call friday 9 am", knownTags: tags).dueDate == day(2026, 10, 23, 9))
        #expect(parser.parse("Meet 12am tomorrow", knownTags: tags).dueDate == day(2026, 10, 22, 0))
    }

    @Test func timeWithoutDayPicksNextOccurrence() {
        #expect(parser.parse("Gym 6pm", knownTags: tags).dueDate == day(2026, 10, 21, 18))
        #expect(parser.parse("Gym 7am", knownTags: tags).dueDate == day(2026, 10, 22, 7))
    }

    @Test func connectorsAreRemovedOnlyNearDates() {
        #expect(parser.parse("Taller a las 3pm", knownTags: tags).title == "Taller")
        #expect(parser.parse("Essay due friday", knownTags: tags).title == "Essay")
        #expect(parser.parse("Write about the war", knownTags: tags).title == "Write about the war")
    }

    @Test func bareNumbersAreNotTimes() {
        let r = parser.parse("Lab 3 #so", knownTags: tags)
        #expect(r.title == "Lab 3")
        #expect(r.dueDate == nil)
    }

    @Test func priority() {
        #expect(parser.parse("Pay fees !", knownTags: tags).priority == 1)
        #expect(parser.parse("Pay fees !!", knownTags: tags).priority == 2)
        #expect(parser.parse("Wow!", knownTags: tags).title == "Wow!")
    }

    @Test func unknownTagStaysInTitle() {
        let r = parser.parse("Buy milk #groceries", knownTags: tags)
        #expect(r.tag == nil)
        #expect(r.title == "Buy milk #groceries")
    }

    @Test func tagIsCaseAndAccentInsensitive() {
        #expect(parser.parse("Taller #SO", knownTags: tags).tag == "so")
    }
}
