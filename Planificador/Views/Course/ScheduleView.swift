import AgendaCore
import SwiftData
import SwiftUI

/// A course's fixed weekly classes. Each slot is a repeating block until the end of the semester.
struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Bindable var area: Area

    @State private var weekdays: Set<Int> = []
    @State private var startTime = CalendarMath().date(.now, atMinutes: 7 * 60)
    @State private var endTime = CalendarMath().date(.now, atMinutes: 9 * 60)
    @State private var location = ""
    @State private var editing: CalendarItem?

    private let math = CalendarMath()

    private var classBlocks: [Block] {
        area.blocks
            .filter { $0.recurrence != nil }
            .sorted { lhs, rhs in
                let l = (firstWeekday(lhs), math.minutesIntoDay(lhs.start))
                let r = (firstWeekday(rhs), math.minutesIntoDay(rhs.start))
                return l < r
            }
    }

    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Weekly Classes")
                if classBlocks.isEmpty {
                    Card {
                        CardRow(icon: "calendar.badge.plus") {
                            Text("No schedule yet. Add this course’s time slots below; they repeat every week until the end of the semester.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Card {
                        ForEach(Array(classBlocks.enumerated()), id: \.element.liveID) { index, block in
                            if index > 0 { CardDivider() }
                            slotRow(block)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Add Time Slot")
                Card {
                    CardRow(icon: "calendar.day.timeline.left") {
                        WeekdayCircles(selection: $weekdays, tint: Color(hex: area.colorHex))
                    }
                    CardDivider()
                    CardRow(icon: "clock") {
                        Text("Time")
                        Spacer()
                        TimePill(time: Binding(
                            get: { startTime },
                            set: { newValue in
                                endTime = newValue.addingTimeInterval(endTime.timeIntervalSince(startTime))
                                startTime = newValue
                            }), showsIcon: false)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        TimePill(time: $endTime, showsIcon: false)
                    }
                    CardDivider()
                    CardRow(icon: "mappin.and.ellipse") {
                        CardTextField(placeholder: "Room (optional)", text: $location)
                    }
                    if let semester = area.semester {
                        CardNote(text: "Repeats until \(semester.endDate.agenda(date: .long, time: .omitted)).")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add to Schedule", systemImage: "plus") { add() }
                        .primaryAction()
                        .disabled(!canAdd)
                }
            }
        }
        .sheet(item: $editing) { item in
            if let semester = area.semester {
                BlockEditorView(target: .existing(item), semester: semester)
            }
        }
    }

    private func slotRow(_ block: Block) -> some View {
        CardRow(icon: "graduationcap.fill", iconColor: Color(hex: area.colorHex)) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(dayList(block.recurrence?.weekdays ?? [])).font(Theme.Font.rowTitle.weight(.medium))
                HStack(spacing: Theme.Space.s) {
                    Text("\(block.start.agenda(date: .omitted, time: .shortened)) – \(block.end.agenda(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                    if !block.location.isEmpty {
                        Label(block.location, systemImage: "mappin")
                    }
                }
                .font(Theme.Font.rowDetail)
                .foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(title: "Edit Time Slot", systemImage: "pencil") { editing = firstItem(of: block) }
                .disabled(firstItem(of: block) == nil)
            IconButton(title: "Remove Time Slot", systemImage: "trash", role: .destructive) {
                withAnimation(Theme.Motion.snappy) { context.delete(block) }
            }
        }
    }

    private var canAdd: Bool {
        !weekdays.isEmpty && math.minutesIntoDay(endTime) > math.minutesIntoDay(startTime) && area.semester != nil
    }

    private func add() {
        guard let semester = area.semester else { return }
        let block = ClassSchedule.makeBlock(
            area: area, semester: semester, weekdays: weekdays,
            startMinutes: math.minutesIntoDay(startTime), endMinutes: math.minutesIntoDay(endTime),
            location: location.trimmingCharacters(in: .whitespaces), math: math)
        withAnimation(Theme.Motion.snappy) { context.insert(block) }
        weekdays = []
        location = ""
    }

    /// An occurrence to open in the editor (the next one, or the first of the series).
    private func firstItem(of block: Block) -> CalendarItem? {
        guard let semester = area.semester else { return nil }
        let interval = DateInterval(start: max(math.startOfDay(.now), semester.startDate), end: math.add(days: 1, to: semester.endDate))
        return CalendarFeed.items(for: [block], in: interval, breaks: semester.breaks, math: math).first
    }

    private func firstWeekday(_ block: Block) -> Int {
        Weekdays.order.firstIndex { block.recurrence?.weekdays.contains($0) == true } ?? 7
    }

    private func dayList(_ days: Set<Int>) -> String {
        Weekdays.order.filter(days.contains).map(Weekdays.name).formatted(.list(type: .and).locale(.agenda))
    }
}

/// Builds weekly class blocks. Shared by the Schedule tab and schedule import.
@MainActor
enum ClassSchedule {
    static func makeBlock(area: Area, semester: Semester, weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, location: String, math: CalendarMath) -> Block {
        // Anchor the series on the semester's first day; occurrences only fall on the chosen weekdays.
        let anchor = semester.startDate
        return Block(
            title: area.name,
            start: math.date(anchor, atMinutes: startMinutes),
            end: math.date(anchor, atMinutes: endMinutes),
            area: area,
            recurrence: WeeklyRecurrence(weekdays: weekdays, until: semester.endDate),
            location: location)
    }
}
