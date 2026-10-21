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
        area.blocks.filter { $0.recurrence != nil }.sorted { math.minutesIntoDay($0.start) < math.minutesIntoDay($1.start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                slots
                addForm
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editing) { item in
            if let semester = area.semester {
                BlockEditorView(target: .existing(item), semester: semester)
            }
        }
    }

    private var slots: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Weekly Classes").font(Theme.Font.sectionTitle)
            if classBlocks.isEmpty {
                Text("No schedule yet. Add this course’s time slots below; they’ll show up every week in the calendar until the end of the semester.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(classBlocks) { block in
                HStack(spacing: Theme.Space.m) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: area.colorHex)).frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayList(block.recurrence?.weekdays ?? [])).font(.body.weight(.medium))
                        HStack(spacing: Theme.Space.s) {
                            Text("\(block.start.agenda(date: .omitted, time: .shortened)) – \(block.end.agenda(date: .omitted, time: .shortened))")
                                .monospacedDigit()
                            if !block.location.isEmpty {
                                Label(block.location, systemImage: "mappin").labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editing = firstItem(of: block) }
                        .disabled(firstItem(of: block) == nil)
                    Button(role: .destructive) {
                        withAnimation(Theme.Motion.snappy) { context.delete(block) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove this time slot")
                }
                .padding(Theme.Space.m)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Add Time Slot").font(Theme.Font.sectionTitle)
            HStack(spacing: Theme.Space.xs) {
                ForEach(Weekdays.order, id: \.self) { weekday in
                    Toggle(Weekdays.short(weekday), isOn: Binding(
                        get: { weekdays.contains(weekday) },
                        set: { if $0 { weekdays.insert(weekday) } else { weekdays.remove(weekday) } }))
                    .toggleStyle(.button)
                    .help(Weekdays.name(weekday))
                }
            }
            HStack(spacing: Theme.Space.l) {
                DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .fixedSize()
            TextField("Room (optional)", text: $location)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            HStack {
                Button("Add to Schedule", systemImage: "plus") { add() }
                    .buttonStyle(.glassProminent)
                    .disabled(weekdays.isEmpty || math.minutesIntoDay(endTime) <= math.minutesIntoDay(startTime) || area.semester == nil)
                if let semester = area.semester {
                    Text("Repeats until \(semester.endDate.agenda(date: .long, time: .omitted)).")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func add() {
        guard let semester = area.semester else { return }
        // Anchor the series on the semester's first day; occurrences only fall on the chosen weekdays.
        let anchor = semester.startDate
        let block = Block(
            title: area.name,
            start: math.date(anchor, keepingTimeOf: startTime),
            end: math.date(anchor, keepingTimeOf: endTime),
            area: area,
            recurrence: WeeklyRecurrence(weekdays: weekdays, until: semester.endDate),
            location: location.trimmingCharacters(in: .whitespaces))
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

    private func dayList(_ days: Set<Int>) -> String {
        Weekdays.order.filter(days.contains).map(Weekdays.name).formatted(.list(type: .and).locale(.agenda))
    }
}
