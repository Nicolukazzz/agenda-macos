import Foundation
import Testing
@testable import AgendaCore

struct ClassAlertTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ title: String, inMinutes minutes: Int, room: String = "") -> ClassAlertPlanner.Class {
        .init(title: title, location: room, start: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    @Test func firesLeadMinutesBeforeEachClass() {
        let alerts = ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 60, room: "204")], leadMinutes: 10, now: now)
        #expect(alerts.count == 1)
        #expect(alerts[0].fireDate == now.addingTimeInterval(50 * 60))
        #expect(alerts[0].title == "BD")
        #expect(alerts[0].location == "204")
        #expect(alerts[0].id.hasPrefix(ClassAlertPlanner.idPrefix))
    }

    @Test func skipsClassesWhoseAlertMomentPassed() {
        // Starts in 5 minutes: the 10-minute alert would have fired already.
        let alerts = ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 5), item("SO", inMinutes: -30)], leadMinutes: 10, now: now)
        #expect(alerts.isEmpty)
    }

    @Test func soonestFirstAndCapped() {
        let classes = (1...80).reversed().map { item("C\($0)", inMinutes: $0 * 100) }
        let alerts = ClassAlertPlanner.alerts(for: classes, leadMinutes: 10, now: now)
        #expect(alerts.count == ClassAlertPlanner.limit)
        #expect(alerts.first?.title == "C1")
        #expect(alerts.map(\.fireDate) == alerts.map(\.fireDate).sorted())
    }

    @Test func idChangesWithTimeLeadTitleAndRoom() {
        let base = ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 60, room: "204")], leadMinutes: 10, now: now)[0].id
        #expect(ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 60, room: "204")], leadMinutes: 10, now: now)[0].id == base)
        #expect(ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 90, room: "204")], leadMinutes: 10, now: now)[0].id != base)
        #expect(ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 60, room: "204")], leadMinutes: 15, now: now)[0].id != base)
        #expect(ClassAlertPlanner.alerts(for: [item("BD", inMinutes: 60, room: "301")], leadMinutes: 10, now: now)[0].id != base)
    }
}
