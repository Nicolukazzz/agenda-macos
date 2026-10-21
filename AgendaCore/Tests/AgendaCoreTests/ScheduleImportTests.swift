import Foundation
import Testing
@testable import AgendaCore

struct ScheduleImportTests {
    @Test func parsesTimes() {
        #expect(ScheduleImportFile.minutes(from: "07:00") == 420)
        #expect(ScheduleImportFile.minutes(from: "17:30") == 1050)
        #expect(ScheduleImportFile.minutes(from: "24:00") == nil)
        #expect(ScheduleImportFile.minutes(from: "7") == nil)
    }

    @Test func decodesAndValidates() throws {
        let json = #"{"semester":"2026-2","slots":[{"tag":"bd","weekdays":[3],"start":"11:00","end":"13:00","room":"SC009-P111"},{"tag":"xx","weekdays":[9],"start":"10:00","end":"09:00"}]}"#
        let file = try JSONDecoder().decode(ScheduleImportFile.self, from: Data(json.utf8))
        #expect(file.slots.count == 2)
        #expect(file.slots[0].room == "SC009-P111")
        let problems = file.problems(knownTags: ["bd"])
        #expect(problems == ["Unknown course #xx", "Bad weekdays for #xx", "Bad time range for #xx"])
    }
}
