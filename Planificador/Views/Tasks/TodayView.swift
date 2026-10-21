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

    var body: some View {
        PageContent {
            QuickAddBar(areas: semester.sortedAreas)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Schedule", detail: Date.now.agenda(.dateTime.weekday(.wide).day().month(.wide)))
                Card {
                    if todayItems.isEmpty {
                        CardRow(icon: "sun.max") { Text("No classes or events today.").foregroundStyle(.secondary) }
                    }
                    ForEach(Array(todayItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { CardDivider() }
                        EventRow(item: item) { editingBlock = $0 }
                    }
                }
            }

            TaskListView(buckets: [.overdue, .today], emptyMessage: "Nothing due today.") { editingTask = $0 }
        }
        .navigationTitle("Today")
        .navigationSubtitle("Semester \(semester.name)")
        .sheet(item: $editingTask) { TaskEditorView(task: $0, semester: semester) }
        .sheet(item: $editingBlock) { BlockEditorView(target: .existing($0), semester: semester) }
    }
}
