import AgendaCore
import SwiftData
import SwiftUI

/// What a new calendar item becomes: a task with a due date (shown in Tasks, Today and the month)
/// or an event that blocks time.
enum NewItemKind: String, CaseIterable, Identifiable {
    case task = "Task"
    case event = "Event"
    var id: Self { self }
}

enum BlockEditorTarget: Identifiable {
    case new(start: Date, end: Date, area: Area?, kind: NewItemKind)
    case existing(CalendarItem)

    var id: String {
        switch self {
        case .new(let start, _, _, let kind): "new-\(kind.rawValue)-\(start.timeIntervalSinceReferenceDate)"
        case .existing(let item): item.id
        }
    }
}

/// Create a task or an event from the calendar, or edit an event. `#tag` in the title assigns the course.
/// Existing one-off events can be converted into tasks.
struct BlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let target: BlockEditorTarget
    let semester: Semester

    @State private var title = ""
    @State private var area: Area?
    @State private var day = Date.now
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var repeats = false
    @State private var weekdays: Set<Int> = []
    @State private var location = ""
    @State private var notes = ""
    @State private var askingScope = false
    @State private var askingDeleteScope = false
    /// Validation messages appear only after a save attempt, never on an untouched form.
    @State private var triedToSave = false
    @State private var kind: NewItemKind = .event
    @State private var taskHasTime = false
    @State private var taskHasDue = true
    @State private var taskPriority = 0
    @State private var taskCreatesReminder = false

    private let math = CalendarMath()

    init(target: BlockEditorTarget, semester: Semester) {
        self.target = target
        self.semester = semester
        let math = CalendarMath()
        switch target {
        case .new(let start, let end, let preset, let kind):
            _kind = State(initialValue: kind)
            _day = State(initialValue: start)
            _startTime = State(initialValue: start)
            _endTime = State(initialValue: end)
            _area = State(initialValue: preset)
            _weekdays = State(initialValue: [math.calendar.component(.weekday, from: start)])
        case .existing(let item):
            let block = item.block
            _title = State(initialValue: block.title)
            _area = State(initialValue: block.area)
            _day = State(initialValue: item.start)
            _startTime = State(initialValue: item.start)
            _endTime = State(initialValue: item.end)
            _repeats = State(initialValue: block.recurrence != nil)
            _weekdays = State(initialValue: block.recurrence?.weekdays ?? [math.calendar.component(.weekday, from: item.start)])
            _location = State(initialValue: block.location)
            _notes = State(initialValue: block.notes)
        }
    }

    private var existing: CalendarItem? {
        if case .existing(let item) = target { return item }
        return nil
    }

    private var isTask: Bool { existing == nil && kind == .task }

    var body: some View {
        SheetScaffold(eyebrow: existing != nil ? "Edit Event" : (isTask ? "New Task" : "New Event")) {
            if existing == nil {
                Picker("Kind", selection: $kind.animation(Theme.Motion.snappy)) {
                    ForEach(NewItemKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("A task has a due date and appears in Tasks and Today; an event blocks time in the calendar.")
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                TagCompletionField(placeholder: "Title", text: $title, areas: semester.sortedAreas, style: .prominent, onSubmit: attemptSave)
                CourseChips(selection: $area, areas: semester.sortedAreas)
            }
            .zIndex(1)

            if isTask {
                taskCards
            } else {
                eventCards
            }

            if let problem, triedToSave || (!isTask && newEnd <= newStart) {
                ValidationMessage(text: problem)
            }
        } footer: {
            ActionBar(
                destructiveTitle: existing == nil ? nil : "Delete",
                onDestructive: {
                    if existing?.isRecurring == true { askingDeleteScope = true } else { deleteNow(.allEvents) }
                },
                onCancel: { dismiss() },
                primaryTitle: "Save",
                onPrimary: attemptSave)
        }
        .animation(Theme.Motion.snappy, value: repeats)
        .animation(Theme.Motion.snappy, value: taskHasTime)
        .animation(Theme.Motion.snappy, value: taskHasDue)
        .confirmationDialog("This event repeats", isPresented: $askingScope) {
            Button("Only This Event") { save(.onlyThis) }
            Button("All Events") { save(.allEvents) }
        } message: {
            Text("Apply the changes to this day only, or to the whole series?")
        }
        .confirmationDialog("This event repeats", isPresented: $askingDeleteScope) {
            Button("Delete Only This Event", role: .destructive) { deleteNow(.onlyThis) }
            Button("Delete All Events", role: .destructive) { deleteNow(.allEvents) }
        }
    }

    // MARK: Sections

    /// Same form as the task editor, so every option (priority, "Create reminder"…) is here too.
    private var taskCards: some View {
        TaskFormCards(
            hasDue: $taskHasDue, dueDay: $day, dueTime: $startTime, hasTime: $taskHasTime,
            priority: $taskPriority, createsReminder: $taskCreatesReminder, notes: $notes)
    }

    @ViewBuilder
    private var eventCards: some View {
            Card {
                CardRow(icon: "calendar") {
                    Text("Day")
                    Spacer()
                    DatePill(date: $day, showsIcon: false)
                }
                CardDivider()
                CardRow(icon: "clock") {
                    Text("Time")
                    Spacer()
                    // Moving the start keeps the duration, like Calendar does.
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
                CardRow(icon: "hourglass") {
                    DurationChips(start: newStart, end: Binding(get: { newEnd }, set: { endTime = $0 }))
                }
            }

            Card {
                CardRow(icon: "repeat", iconColor: repeats ? .accentColor : .secondary) {
                    CardToggle(title: "Repeats every week", isOn: $repeats)
                }
                if repeats {
                    CardDivider()
                    CardRow(icon: "calendar.day.timeline.left") {
                        WeekdayCircles(selection: $weekdays, tint: area.map { Color(hex: $0.colorHex) } ?? .accentColor)
                    }
                    CardNote(text: "Until the end of semester \(semester.name). Skips breaks.")
                }
            }

            Card {
                CardRow(icon: "mappin.and.ellipse") { CardTextField(placeholder: "Location", text: $location) }
                CardDivider()
                CardRow(icon: "text.alignleft") { CardTextField(placeholder: "Notes", text: $notes, axis: .vertical) }
            }

            if let item = existing, !item.isRecurring {
                Card {
                    CardRow(icon: "checklist") {
                        Text("Is this a deadline?")
                        Spacer()
                        Button("Convert to Task") { convertToTask(item) }
                            .buttonStyle(.glass)
                    }
                    CardNote(text: "Tasks show up in Tasks, Today and the course’s Tasks tab.")
                }
            }
    }

    // MARK: State

    private func binding(for weekday: Int) -> Binding<Bool> {
        Binding(
            get: { weekdays.contains(weekday) },
            set: { isOn in if isOn { weekdays.insert(weekday) } else { weekdays.remove(weekday) } })
    }

    private var resolved: (title: String, area: Area?) {
        let known = Set(semester.sortedAreas.map(\.tag))
        let extracted = TagCompletion.extract(from: title, known: known)
        let taggedArea = extracted.tag.flatMap { tag in semester.sortedAreas.first { $0.tag == tag } }
        return (extracted.title.trimmingCharacters(in: .whitespaces), taggedArea ?? area)
    }

    private var newStart: Date { math.date(day, keepingTimeOf: startTime) }
    private var newEnd: Date { math.date(day, keepingTimeOf: endTime) }

    private var problem: String? {
        if resolved.title.isEmpty && resolved.area == nil { return "Enter a title or pick a course." }
        if isTask { return nil }
        if newEnd <= newStart { return "The end time must be after the start time." }
        if repeats && weekdays.isEmpty { return "Pick at least one day." }
        return nil
    }

    // MARK: Actions

    private func attemptSave() {
        triedToSave = true
        guard problem == nil else { return }
        if isTask {
            saveTask()
            return
        }
        if existing?.isRecurring == true { askingScope = true } else { save(.allEvents) }
    }

    private func save(_ scope: ChangeScope) {
        let (cleanTitle, finalArea) = resolved
        let finalTitle = cleanTitle.isEmpty ? (finalArea?.name ?? "") : cleanTitle
        let recurrence = repeats ? WeeklyRecurrence(weekdays: weekdays, until: semester.endDate) : nil

        if let item = existing {
            var block = item.block
            if item.isRecurring && scope == .onlyThis {
                block = BlockActions.detach(item, context: context, math: math)
                block.start = newStart
                block.end = newEnd
            } else if item.isRecurring && recurrence != nil {
                BlockActions.reschedule(item, to: newStart, end: newEnd, scope: .allEvents, context: context, math: math)
                block.recurrence = recurrence
            } else {
                block.start = newStart
                block.end = newEnd
                block.recurrence = recurrence
            }
            block.title = finalTitle
            block.area = finalArea
            block.location = location
            block.notes = notes
        } else {
            let block = Block(title: finalTitle, start: newStart, end: newEnd, area: finalArea, recurrence: recurrence, location: location, notes: notes)
            context.insert(block)
        }
        try? context.save()
        dismiss()
    }

    private func saveTask() {
        let (cleanTitle, finalArea) = resolved
        let due = taskHasDue ? (taskHasTime ? newStart : math.date(day, atMinutes: 23 * 60 + 59)) : nil
        let task = TaskItem(
            title: cleanTitle.isEmpty ? (finalArea?.name ?? "Task") : cleanTitle,
            dueDate: due, dueHasTime: taskHasDue && taskHasTime, area: finalArea, priority: taskPriority, notes: notes)
        task.createsReminder = taskCreatesReminder
        context.insert(task)
        try? context.save()
        dismiss()
    }

    /// Turns a one-off event into a task due at the event's start; the event is removed.
    private func convertToTask(_ item: CalendarItem) {
        let (cleanTitle, finalArea) = resolved
        let task = TaskItem(
            title: cleanTitle.isEmpty ? item.block.title : cleanTitle,
            dueDate: newStart, dueHasTime: true, area: finalArea, notes: notes)
        context.insert(task)
        context.delete(item.block)
        try? context.save()
        dismiss()
    }

    private func deleteNow(_ scope: ChangeScope) {
        guard let item = existing else { return }
        BlockActions.delete(item, scope: scope, context: context, math: math)
        try? context.save()
        dismiss()
    }
}
