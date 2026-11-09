import AgendaCore
import SwiftData
import SwiftUI

/// Edit a task in place: title (`#tag` works), course, due date, priority, subtasks, notes,
/// and work blocks scheduled in the calendar. Changes apply live; ⌘Z undoes them.
struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var task: TaskItem
    let semester: Semester

    @State private var title = ""
    @State private var hasDue = false
    @State private var dueDay = Date.now
    @State private var dueTime = CalendarMath().date(.now, atMinutes: 23 * 60 + 59)
    @State private var newSubtask = ""
    @State private var blockDay = Date.now
    @State private var blockStart = CalendarMath().date(.now, atMinutes: 16 * 60)
    @State private var confirmingDelete = false

    private let math = CalendarMath()

    /// State starts from the task so the sheet opens in its final layout (no animated jump).
    init(task: TaskItem, semester: Semester) {
        self.task = task
        self.semester = semester
        let math = CalendarMath()
        _title = State(initialValue: task.title)
        _hasDue = State(initialValue: task.dueDate != nil)
        _dueDay = State(initialValue: task.dueDate ?? .now)
        _dueTime = State(initialValue: task.dueDate ?? math.date(.now, atMinutes: 23 * 60 + 59))
        let suggested = task.dueDate.map { math.add(days: -1, to: $0) } ?? .now
        _blockDay = State(initialValue: max(suggested, .now))
    }

    var body: some View {
        SheetScaffold(eyebrow: "Task") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.m) {
                    CheckCircle(isOn: task.isDone, colorHex: task.displayColorHex, size: 20) { task.toggleDone() }
                    TagCompletionField(placeholder: "Title", text: $title, areas: semester.sortedAreas, style: .prominent, onSubmit: commitTitle)
                }
                CourseChips(selection: $task.area, areas: semester.sortedAreas)
            }
            .zIndex(1)

            Card {
                CardRow(icon: "calendar", iconColor: hasDue ? .accentColor : .secondary) {
                    CardToggle(title: "Due date", isOn: $hasDue)
                }
                if hasDue {
                    CardDivider()
                    CardRow(icon: "calendar.badge.exclamationmark") {
                        Text("Day")
                        Spacer()
                        DatePill(date: $dueDay, showsIcon: false)
                    }
                    CardDivider()
                    CardRow(icon: "clock", iconColor: task.dueHasTime ? .accentColor : .secondary) {
                        Text("Time")
                        Spacer()
                        if task.dueHasTime {
                            TimePill(time: $dueTime, showsIcon: false)
                        }
                        Toggle("Time", isOn: $task.dueHasTime).toggleStyle(.switch).labelsHidden()
                    }
                }
                CardDivider()
                CardRow(icon: "exclamationmark.circle") {
                    Text("Priority")
                    Spacer()
                    Chip(title: "None", isSelected: task.priority == 0) { task.priority = 0 }
                    Chip(title: "! High", colorHex: "#F0A33A", isSelected: task.priority == 1, showsDot: false) { task.priority = 1 }
                    Chip(title: "!! Urgent", colorHex: "#E5534B", isSelected: task.priority == 2, showsDot: false) { task.priority = 2 }
                }
            }

            reminderCard
            subtasksCard
            scheduleCard

            Card {
                CardRow(icon: "text.alignleft") { CardTextField(placeholder: "Notes", text: $task.notes, axis: .vertical) }
            }
        } footer: {
            ActionBar(
                destructiveTitle: "Delete",
                onDestructive: { confirmingDelete = true },
                cancelTitle: nil,
                primaryTitle: "Done",
                onPrimary: close)
        }
        .animation(Theme.Motion.snappy, value: hasDue)
        .animation(Theme.Motion.snappy, value: task.dueHasTime)
        .onChange(of: hasDue) { applyDue() }
        .onChange(of: dueDay) { applyDue() }
        .onChange(of: dueTime) { applyDue() }
        .onChange(of: task.dueHasTime) { applyDue() }
        .onChange(of: task.createsReminder) {
            if task.createsReminder { Task { await appState.reminders.requestAccess() } }
        }
        .animation(Theme.Motion.snappy, value: task.createsReminder)
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmingDelete) {
            Button("Delete Task", role: .destructive) {
                context.delete(task)
                try? context.save()
                dismiss()
            }
        }
    }

    // MARK: Reminders

    private var reminderCard: some View {
        Card {
            CardRow(icon: "checklist", iconColor: task.createsReminder ? .accentColor : .secondary) {
                CardToggle(title: "Create reminder", isOn: $task.createsReminder)
            }
            if task.createsReminder {
                CardNote(text: reminderNote)
            }
        }
    }

    private var reminderNote: String {
        switch appState.reminders.access {
        case .granted: "Synced with Reminders and your iPhone. Turning this off removes the reminder."
        case .notDetermined: "Agenda will ask for access to Reminders."
        case .denied: "Agenda can’t reach Reminders. Allow it in System Settings › Privacy & Security › Reminders."
        }
    }

    // MARK: Subtasks

    private var sortedSubtasks: [Subtask] { task.subtasks.sorted { $0.order < $1.order } }

    private var subtasksCard: some View {
        Card {
            ForEach(sortedSubtasks, id: \.liveID) { subtask in
                SubtaskRow(subtask: subtask, colorHex: task.displayColorHex) {
                    withAnimation(Theme.Motion.snappy) { context.delete(subtask) }
                }
                CardDivider()
            }
            CardRow(icon: "plus") {
                CardTextField(placeholder: "Add subtask", text: $newSubtask)
                    .onSubmit(addSubtask)
            }
        }
    }

    private func addSubtask() {
        let titleText = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !titleText.isEmpty else { return }
        let subtask = Subtask(title: titleText, order: (task.subtasks.map(\.order).max() ?? -1) + 1)
        withAnimation(Theme.Motion.snappy) { task.subtasks.append(subtask) }
        newSubtask = ""
    }

    // MARK: Schedule work

    private var scheduleCard: some View {
        Card {
            ForEach(task.scheduledBlocks.sorted { $0.start < $1.start }, id: \.liveID) { block in
                CardRow(icon: "calendar.badge.clock", iconColor: .accentColor) {
                    Text(block.start.agenda(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    Text("\(block.start.agenda(date: .omitted, time: .shortened)) – \(block.end.agenda(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    IconButton(title: "Remove Work Block", systemImage: "trash", role: .destructive) {
                        withAnimation(Theme.Motion.snappy) { context.delete(block) }
                    }
                }
                CardDivider()
            }
            CardRow(icon: "calendar.badge.plus") {
                Text("Work on it")
                Spacer()
                DatePill(date: $blockDay, showsIcon: false)
                TimePill(time: $blockStart, showsIcon: false)
                Button("Add 1h") { scheduleBlock() }.buttonStyle(.glass)
            }
            CardNote(text: "Reserves time in the calendar for this task.")
        }
    }

    private func scheduleBlock() {
        let start = math.date(blockDay, keepingTimeOf: blockStart)
        let block = Block(title: task.title, start: start, end: start.addingTimeInterval(3600), area: task.area)
        block.linkedTask = task
        withAnimation(Theme.Motion.snappy) { context.insert(block) }
    }

    // MARK: State

    private func applyDue() {
        guard hasDue else {
            task.dueDate = nil
            task.dueHasTime = false
            return
        }
        task.dueDate = task.dueHasTime
            ? math.date(dueDay, keepingTimeOf: dueTime)
            : math.date(dueDay, atMinutes: 23 * 60 + 59)
    }

    /// `#tag` typed in the title moves the task to that course.
    private func commitTitle() {
        let extracted = TagCompletion.extract(from: title, known: Set(semester.sortedAreas.map(\.tag)))
        if let tag = extracted.tag { task.area = semester.sortedAreas.first { $0.tag == tag } }
        let clean = extracted.title.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { task.title = clean }
        title = task.title
    }

    private func close() {
        commitTitle()
        try? context.save()
        dismiss()
    }
}

private struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    let colorHex: String
    var onDelete: () -> Void

    var body: some View {
        CardRow {
            CheckCircle(isOn: subtask.isDone, colorHex: colorHex, size: 15) {
                withAnimation(Theme.Motion.snappy) { subtask.isDone.toggle() }
            }
            CardTextField(placeholder: "Subtask", text: $subtask.title)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? .secondary : .primary)
            IconButton(title: "Remove Subtask", systemImage: "xmark", action: onDelete)
        }
    }
}
