import Foundation
import Testing
@testable import AgendaCore

/// Runs against a throwaway copy of the folder layout, never the user's real classes.
final class FolderScannerTests {
    let root: URL

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "agenda-tests-\(UUID().uuidString)")
        let folders = [
            "2026-2/BD/Presentaciones", "2026-2/Sistemas Operativos", "2026-2/Gestión TI",
            "2026-1/Calculo", "Material suelto", "2025-10",
        ]
        for folder in folders {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appending(path: "2026-2/notas.txt"))
        try FileManager.default.createDirectory(at: root.appending(path: "2026-2/.oculta"), withIntermediateDirectories: true)
    }

    @Test func findsSemestersNewestFirst() throws {
        let names = try FolderScanner.semesters(in: root).map(\.name)
        #expect(names == ["2026-2", "2026-1", "2025-10"])
    }

    @Test func listsCourseFoldersOnly() throws {
        let semester = root.appending(path: "2026-2")
        let names = try FolderScanner.courses(in: semester).map(\.name)
        #expect(names == ["BD", "Gestión TI", "Sistemas Operativos"])
    }

    @Test func nextSemester() {
        #expect(FolderScanner.nextSemesterName(after: "2026-2") == "2027-1")
        #expect(FolderScanner.nextSemesterName(after: "2026-1") == "2026-2")
        #expect(FolderScanner.nextSemesterName(after: "otoño") == nil)
    }
}

struct TagSuggesterTests {
    @Test(arguments: [
        ("BD", "bd"),
        ("Sistemas Operativos", "so"),
        ("Gestión TI", "gti"),
        ("Fundamentos de la Ingenieria", "fi"),
        ("Sistemas de la Informacion", "si"),
        ("Teoria de la Computacion", "tc"),
        ("Teologia", "teologia"),
    ])
    func suggestsShortTags(name: String, expected: String) {
        #expect(TagSuggester.suggest(for: name) == expected)
    }

    @Test func avoidsDuplicates() {
        #expect(TagSuggester.suggest(for: "Sistemas Operativos", existing: ["so"]) == "so2")
        #expect(TagSuggester.suggest(for: "Sistemas Operativos", existing: ["so", "so2"]) == "so3")
    }

    @Test func normalizesAccentsAndCase() {
        #expect(TagSuggester.normalize("Gestión-TI") == "gestionti")
    }
}

struct SemesterDatesTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }()

    @Test func secondTermIsJulyToDecember() throws {
        let dates = try #require(SemesterDates.range(for: "2026-2", calendar: calendar))
        #expect(calendar.dateComponents([.month, .day], from: dates.start) == DateComponents(month: 7, day: 1))
        #expect(calendar.dateComponents([.month, .day], from: dates.end) == DateComponents(month: 12, day: 31))
    }

    @Test func firstTermIsJanuaryToJune() throws {
        let dates = try #require(SemesterDates.range(for: "2027-1", calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day], from: dates.start) == DateComponents(year: 2027, month: 1, day: 1))
        #expect(calendar.dateComponents([.month, .day], from: dates.end) == DateComponents(month: 6, day: 30))
    }

    @Test func rejectsOtherNames() {
        #expect(SemesterDates.range(for: "sin-fecha") == nil)
        #expect(SemesterDates.range(for: "2026-3") == nil)
    }
}
