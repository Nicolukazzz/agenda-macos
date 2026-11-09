import AgendaCore
import SwiftData
import SwiftUI

/// What needs attention now: overdue and today's tasks, plus today's classes and blocks.
struct TodayView: View {
    let semester: Semester

    @Query private var blocks: [Block]
    @Query private var tasks: [TaskItem]
    @Query(sort: \MoneyEntry.date, order: .reverse) private var money: [MoneyEntry]
    @Environment(AppState.self) private var appState
    @Environment(\.now) private var now
    @State private var editingTask: TaskItem?
    @State private var editingBlock: CalendarItem?

    private let math = CalendarMath()

    private var todayItems: [CalendarItem] {
        let start = math.startOfDay(.now)
        return CalendarFeed.items(for: blocks, in: DateInterval(start: start, end: math.add(days: 1, to: start)), breaks: semester.breaks, math: math)
    }

    /// Tasks due by today (or overdue) in the active semester, plus everything checked off today.
    private var progress: (done: Int, total: Int) {
        let relevant = tasks.filter { task in
            guard task.area.map({ $0.semester?.isActive == true }) ?? true else { return false }
            if task.isDone { return task.completedAt.map { math.isSameDay($0, .now) } ?? false }
            let bucket = TaskBucket.bucket(due: task.dueDate, hasTime: task.dueHasTime, now: now, math: math)
            return bucket == .overdue || bucket == .today
        }
        return (relevant.filter(\.isDone).count, relevant.count)
    }

    /// A titled card of today's calendar items (classes or the user's own events).
    private func itemSection(_ title: String, detail: String? = nil, items: [CalendarItem], emptyIcon: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title, detail: detail)
            Card {
                if items.isEmpty {
                    CardRow(icon: emptyIcon) { Text(emptyText).foregroundStyle(.secondary) }
                }
                // Today's "now" line sits before the first event still to come, unless one is happening.
                let nowIndex = items.contains { $0.start <= now && $0.end > now } ? nil : (items.firstIndex { $0.start > now } ?? items.count)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index == nowIndex { NowDivider(time: now) } else if index > 0 { CardDivider() }
                    EventRow(item: item) { editingBlock = $0 }
                }
                if nowIndex == items.count && !items.isEmpty { NowDivider(time: now) }
            }
        }
    }

    var body: some View {
        PageContent {
            QuickAddBar(areas: semester.sortedAreas)

            itemSection(
                "Classes",
                detail: Date.now.agenda(.dateTime.weekday(.wide).day().month(.wide)),
                items: todayItems.filter(\.block.isClassSchedule),
                emptyIcon: "graduationcap",
                emptyText: "No classes today.")

            itemSection(
                "Schedule",
                items: todayItems.filter { !$0.block.isClassSchedule },
                emptyIcon: "calendar",
                emptyText: "Nothing else scheduled today.")

            let progress = progress
            if progress.total > 0 {
                DayProgressCard(done: progress.done, total: progress.total)
            }
            if progress.total == 0 || progress.done < progress.total {
                TaskListView(buckets: [.overdue, .today], hidesCompleted: true, emptyMessage: "Nothing due today.") { editingTask = $0 }
            }

            moneySection
        }
        .navigationTitle("Today")
        .navigationSubtitle("Semester \(semester.name)")
        .sheet(item: $editingTask) { TaskEditorView(task: $0, semester: semester) }
        .sheet(item: $editingBlock) { BlockEditorView(target: .existing($0), semester: semester) }
    }

    // MARK: Money

    /// Spent today and this month, in the display currency. Click to open Money.
    private var moneySection: some View {
        let display = MoneyService.displayCurrency
        let today = math.startOfDay(now)
        let monthStart = math.startOfMonth(containing: now)
        let month = money.prefix { $0.date >= monthStart }.filter { $0.date <= now }
        let spentToday = MoneyTotals(month.filter { $0.date >= today }.map(\.value), in: display).expense
        let totals = MoneyTotals(month.map(\.value), in: display)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: "Money", detail: nil) {
                Button("Open Money", systemImage: "arrow.up.right") { appState.selection = .money }
                    .labelStyle(.iconOnly).buttonStyle(.glass).help("Open Money")
            }
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "Spent Today", systemImage: "cup.and.saucer", value: display.format(spentToday))
                StatTile(title: "This Month", systemImage: "calendar", value: display.format(totals.expense),
                         detail: totals.income > 0 ? "Balance \(display.format(totals.net, signed: true))" : nil)
            }
        }
    }
}
