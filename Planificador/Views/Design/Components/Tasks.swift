import AgendaCore
import SwiftData
import SwiftUI

// How tasks look everywhere: rows, due labels, priority and the quick-add bar.

/// "Today 18:00", "Tomorrow", "Fri", "Nov 21" — red when overdue.
struct DueLabel: View {
    let task: TaskItem
    var math = CalendarMath()
    @Environment(\.now) private var now

    var body: some View {
        if let due = task.dueDate {
            let overdue = !task.isDone && TaskBucket.bucket(due: due, hasTime: task.dueHasTime, now: now, math: math) == .overdue
            Label(Self.text(for: due, hasTime: task.dueHasTime, math: math), systemImage: "calendar")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(overdue ? AnyShapeStyle(Theme.Palette.danger) : AnyShapeStyle(.secondary))
        }
    }

    static func text(for due: Date, hasTime: Bool, math: CalendarMath) -> String {
        let today = math.startOfDay(.now)
        let dueDay = math.startOfDay(due)
        let days = math.calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        let dayText: String
        switch days {
        case 0: dayText = "Today"
        case 1: dayText = "Tomorrow"
        case -1: dayText = "Yesterday"
        case 2..<7: dayText = due.agenda(.dateTime.weekday(.wide))
        default: dayText = due.agenda(.dateTime.day().month(.abbreviated))
        }
        return hasTime ? "\(dayText) \(due.agenda(date: .omitted, time: .shortened))" : dayText
    }
}

/// `!` / `!!` marker.
struct PriorityMark: View {
    let priority: Int

    var body: some View {
        if priority > 0 {
            Text(String(repeating: "!", count: priority))
                .font(Theme.Font.rowDetail.weight(.heavy))
                .foregroundStyle(priority == 2 ? Theme.Palette.danger : Theme.Palette.warning)
                .accessibilityLabel(priority == 2 ? "Urgent" : "High priority")
        }
    }
}

/// A task in a list card: complete, title, course and due date. Click opens it.
struct TaskRow: View {
    @Bindable var task: TaskItem
    var showsCourse = true
    var onOpen: (TaskItem) -> Void

    var body: some View {
        CardRow {
            CheckCircle(isOn: task.isDone, colorHex: task.displayColorHex, size: 22) { task.toggleDone() }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.xs) {
                    PriorityMark(priority: task.priority)
                    Text(task.title)
                        .font(Theme.Font.rowTitle)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)
                }
                HStack(spacing: Theme.Space.s) {
                    if showsCourse, let area = task.area {
                        TagPill(tag: area.tag, colorHex: area.colorHex)
                    }
                    DueLabel(task: task)
                    if !task.subtasks.isEmpty {
                        Label("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count)", systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }
                    if !task.scheduledBlocks.isEmpty {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                            .help("Scheduled in the calendar")
                    }
                }
                .font(Theme.Font.caption)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(task) }
        .accessibilityElement(children: .contain)
    }
}

/// Glass bar to add a task in one line: `Lab report #so friday 6pm !`.
/// Shows how the text will be understood before pressing Return.
struct QuickAddBar: View {
    @Environment(\.modelContext) private var context
    let areas: [Area]
    /// Prefilled course (e.g. inside a course page).
    var defaultArea: Area?
    var focusOnAppear = false
    var onAdded: () -> Void = {}

    @State private var text = ""

    private var parsed: QuickAddResult {
        QuickAddParser().parse(text, knownTags: Set(areas.map(\.tag)))
    }

    private var parsedArea: Area? {
        parsed.tag.flatMap { tag in areas.first { $0.tag == tag } } ?? defaultArea
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                TagCompletionField(
                    placeholder: "Add a task — “Lab report #so friday 6pm !”",
                    text: $text, areas: areas, style: .plain, autofocus: focusOnAppear, onSubmit: add)
            }
            .font(Theme.Font.rowTitle)
            .padding(.horizontal, Theme.Space.l + 2)
            .padding(.vertical, Theme.Space.m + 3)
            .glassEffect(.regular.interactive(), in: .capsule)

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                preview.padding(.leading, Theme.Space.l).transition(.opacity)
            }
        }
        .animation(Theme.Motion.snappy, value: text.isEmpty)
        .zIndex(5)
    }

    private var preview: some View {
        HStack(spacing: Theme.Space.s) {
            Text(parsed.title.isEmpty ? "Untitled" : parsed.title)
                .font(Theme.Font.caption.weight(.semibold))
                .lineLimit(1)
            if let area = parsedArea { TagPill(tag: area.tag, colorHex: area.colorHex) }
            if let due = parsed.dueDate {
                Label(DueLabel.text(for: due, hasTime: parsed.hasTime, math: CalendarMath()), systemImage: "calendar")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
            PriorityMark(priority: parsed.priority)
            Spacer()
            Text("↩ to add").font(Theme.Font.caption).foregroundStyle(.tertiary)
        }
    }

    private func add() {
        let result = parsed
        guard !result.title.isEmpty || parsedArea != nil else { return }
        let math = CalendarMath()
        let due = result.dueDate.map { result.hasTime ? $0 : math.date($0, atMinutes: 23 * 60 + 59) }
        let task = TaskItem(
            title: result.title.isEmpty ? (parsedArea?.name ?? "Task") : result.title,
            dueDate: due, dueHasTime: result.hasTime, area: parsedArea, priority: result.priority)
        withAnimation(Theme.Motion.snappy) { context.insert(task) }
        try? context.save()
        text = ""
        onAdded()
    }
}
