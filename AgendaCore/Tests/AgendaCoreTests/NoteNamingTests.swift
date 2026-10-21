import Foundation
import Testing
@testable import AgendaCore

struct NoteNamingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }()
    var date: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))! }

    @Test func sanitizesForbiddenCharacters() {
        #expect(NoteNaming.sanitize("Clase 3: Normalización / 3FN?") == "Clase 3 Normalización 3FN")
        #expect(NoteNaming.sanitize("   ") == "Untitled")
        #expect(NoteNaming.sanitize("..hidden.") == "hidden")
    }

    @Test func datedFileName() {
        let name = NoteNaming.fileName(title: "Normalización", date: date, calendar: calendar) { _ in false }
        #expect(name == "2026-10-21 Normalización.md")
    }

    @Test func addsCounterForDuplicates() {
        let taken: Set<String> = ["2026-10-21 Repaso.md", "2026-10-21 Repaso (2).md"]
        let name = NoteNaming.fileName(title: "Repaso", date: date, calendar: calendar) { taken.contains($0) }
        #expect(name == "2026-10-21 Repaso (3).md")
    }

    @Test func displayTitlePrefersHeading() {
        #expect(NoteNaming.displayTitle(fileName: "2026-10-21 x.md", contents: "\n# Joins y subconsultas\ntexto") == "Joins y subconsultas")
        #expect(NoteNaming.displayTitle(fileName: "2026-10-21 Repaso.md", contents: "sin título") == "Repaso")
        #expect(NoteNaming.displayTitle(fileName: "CLAUDE.md", contents: nil) == "CLAUDE")
    }
}
