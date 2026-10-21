import AgendaCore
import SwiftData
import SwiftUI

/// Calendar page: month (main) or week, with navigation in the window toolbar.
struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    let semester: Semester

    @Query private var blocks: [Block]
    @Query(filter: #Predicate<TaskItem> { $0.dueDate != nil }) private var dueTasks: [TaskItem]

    @State private var editorTarget: BlockEditorTarget?
    @State private var editingTask: TaskItem?
    @State private var pendingChange: PendingChange?

    private let math = CalendarMath()

    private struct PendingChange {
        let item: CalendarItem
        let start: Date
        let end: Date
    }

    var body: some View {
        @Bindable var appState = appState
        let interval = visibleInterval
        let items = CalendarFeed.items(for: blocks, in: interval, breaks: semester.breaks, math: math)
        let tasks = dueTasks.filter { task in task.dueDate.map { interval.contains($0) } ?? false }

        Group {
            switch appState.calendarMode {
            case .month:
                MonthView(
                    anchor: appState.calendarAnchor, items: items, tasks: tasks,
                    showClasses: appState.showClassesInMonth, math: math,
                    onOpen: { editorTarget = .existing($0) },
                    onOpenTask: { editingTask = $0 },
                    onCreate: { day in editorTarget = newTarget(on: day) },
                    onOpenDay: { day in
                        withAnimation(Theme.Motion.standard) {
                            appState.calendarAnchor = day
                            appState.calendarMode = .week
                        }
                    },
                    onDrop: handleDrop
                )
            case .week:
                WeekView(
                    anchor: appState.calendarAnchor, items: items, tasks: tasks, math: math,
                    onOpen: { editorTarget = .existing($0) },
                    onOpenTask: { editingTask = $0 },
                    onCreate: { start, end in editorTarget = .new(start: start, end: end, area: nil) },
                    onReschedule: requestReschedule,
                    onDrop: handleDrop,
                    onDropAtTime: handleDropAtTime
                )
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(item: $editorTarget) { target in
            BlockEditorView(target: target, semester: semester)
        }
        .sheet(item: $editingTask) { TaskEditorView(task: $0, semester: semester) }
        .confirmationDialog(
            "This event repeats",
            isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } })
        ) {
            Button("Only This Event") { applyPending(.onlyThis) }
            Button("All Events") { applyPending(.allEvents) }
        } message: {
            Text("Move only this day, or the whole series?")
        }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress("t") { goToToday(); return .handled }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var appState = appState
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                Button("Today") { goToToday() }
                Button("Next", systemImage: "chevron.right") { step(1) }
            }
            .help("← → to move, T for today")
        }
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $appState.calendarMode.animation(Theme.Motion.standard)) {
                ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if appState.calendarMode == .month {
                Toggle(isOn: $appState.showClassesInMonth.animation(Theme.Motion.snappy)) {
                    Label("Show Classes", systemImage: "graduationcap")
                }
                .help("Show full class events instead of compact tags")
            }
            Button("New Event", systemImage: "plus") {
                editorTarget = newTarget(on: appState.calendarMode == .month && !math.isSameMonth(appState.calendarAnchor, .now) ? appState.calendarAnchor : .now)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    // MARK: Navigation

    private var visibleInterval: DateInterval {
        switch appState.calendarMode {
        case .month:
            let grid = math.monthGrid(containing: appState.calendarAnchor)
            let start = grid.first?.first ?? appState.calendarAnchor
            let end = math.add(days: 1, to: grid.last?.last ?? start)
            return DateInterval(start: start, end: end)
        case .week:
            let start = math.startOfWeek(containing: appState.calendarAnchor)
            return DateInterval(start: start, end: math.add(days: 7, to: start))
        }
    }

    private var title: String {
        appState.calendarMode == .month
            ? appState.calendarAnchor.agenda(.dateTime.month(.wide).year()).capitalized
            : weekTitle
    }

    private var weekTitle: String {
        let days = math.weekDays(containing: appState.calendarAnchor)
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = math.isSameMonth(first, last)
        let left = first.agenda(sameMonth ? .dateTime.day() : .dateTime.day().month(.abbreviated))
        return "\(left) – \(last.agenda(.dateTime.day().month(.abbreviated).year()))"
    }

    private var subtitle: String { "Semester \(semester.name)" }

    private func step(_ direction: Int) {
        withAnimation(Theme.Motion.standard) {
            appState.calendarAnchor = appState.calendarMode == .month
                ? math.add(months: direction, to: appState.calendarAnchor)
                : math.add(days: 7 * direction, to: appState.calendarAnchor)
        }
    }

    private func goToToday() {
        withAnimation(Theme.Motion.standard) { appState.calendarAnchor = .now }
    }

    private func newTarget(on day: Date) -> BlockEditorTarget {
        let start = math.date(day, atMinutes: 9 * 60)
        return .new(start: start, end: start.addingTimeInterval(3600), area: nil)
    }

    // MARK: Changes

    private func requestReschedule(_ item: CalendarItem, _ start: Date, _ end: Date) {
        if item.isRecurring {
            pendingChange = PendingChange(item: item, start: start, end: end)
        } else {
            withAnimation(Theme.Motion.snappy) {
                BlockActions.reschedule(item, to: start, end: end, scope: .allEvents, context: context, math: math)
            }
        }
    }

    private func applyPending(_ scope: ChangeScope) {
        guard let change = pendingChange else { return }
        withAnimation(Theme.Motion.snappy) {
            BlockActions.reschedule(change.item, to: change.start, end: change.end, scope: scope, context: context, math: math)
        }
        pendingChange = nil
    }

    /// Dropping a task on the hour grid reserves an hour of work for it; events dropped there move.
    private func handleDropAtTime(_ payload: String, _ start: Date) -> Bool {
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        if parts[0] == "task", let task = dueTasks.first(where: { CalendarFeed.key(for: $0) == parts[1] }) {
            let block = Block(title: task.title, start: start, end: start.addingTimeInterval(3600), area: task.area)
            block.linkedTask = task
            withAnimation(Theme.Motion.snappy) { context.insert(block) }
            return true
        }
        return handleDrop(payload, start)
    }

    /// Dropping an event or a task on a day moves it there, keeping its time.
    private func handleDrop(_ payload: String, _ day: Date) -> Bool {
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "block":
            let items = CalendarFeed.items(for: blocks, in: visibleInterval, breaks: semester.breaks, math: math)
            guard let item = items.first(where: { $0.id == parts[1] }), !math.isSameDay(item.start, day) else { return false }
            let start = math.date(day, keepingTimeOf: item.start)
            requestReschedule(item, start, start.addingTimeInterval(item.end.timeIntervalSince(item.start)))
            return true
        case "task":
            guard let task = dueTasks.first(where: { CalendarFeed.key(for: $0) == parts[1] }) else { return false }
            let due = task.dueDate ?? day
            withAnimation(Theme.Motion.snappy) {
                task.dueDate = task.dueHasTime ? math.date(day, keepingTimeOf: due) : math.date(day, atMinutes: 23 * 60 + 59)
            }
            return true
        default:
            return false
        }
    }
}
