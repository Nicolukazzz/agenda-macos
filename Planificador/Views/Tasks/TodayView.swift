import AgendaCore
import SwiftData
import SwiftUI

/// What needs attention now: overdue and today's tasks, plus today's classes and blocks.
struct TodayView: View {
    let semester: Semester

    @Query private var blocks: [Block]
    @State private var editingTask: TaskItem?
    @State private var editingBlock: CalendarItem?

    private let math = CalendarMath()

    private var todayItems: [CalendarItem] {
        let start = math.startOfDay(.now)
        return CalendarFeed.items(for: blocks, in: DateInterval(start: start, end: math.add(days: 1, to: start)), breaks: semester.breaks, math: math)
    }

    /// A titled card of today's calendar items (classes or the user's own events).
    private func itemSection(_ title: String, detail: String? = nil, items: [CalendarItem], emptyIcon: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title, detail: detail)
            Card {
                if items.isEmpty {
                    CardRow(icon: emptyIcon) { Text(emptyText).foregroundStyle(.secondary) }
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { CardDivider() }
                    EventRow(item: item) { editingBlock = $0 }
                }
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

            TaskListView(buckets: [.overdue, .today], emptyMessage: "Nothing due today.") { editingTask = $0 }
        }
        .navigationTitle("Today")
        .navigationSubtitle("Semester \(semester.name)")
        .sheet(item: $editingTask) { TaskEditorView(task: $0, semester: semester) }
        .sheet(item: $editingBlock) { BlockEditorView(target: .existing($0), semester: semester) }
    }
}
