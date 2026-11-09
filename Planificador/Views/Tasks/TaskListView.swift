import AgendaCore
import SwiftData
import SwiftUI

/// Tasks grouped by due bucket (Overdue, Today, Tomorrow…), as cards. Reused by Tasks, Today and course pages.
struct TaskListView: View {
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Environment(\.now) private var now

    var area: Area?
    var buckets: [TaskBucket] = TaskBucket.allCases
    var showCompleted = false
    /// Done tasks leave the list right away (Today: only what is still to do).
    var hidesCompleted = false
    /// Shown (under `emptyTitle`) when no task matches.
    var emptyTitle = "Tasks"
    var emptyMessage = "Nothing here. Add a task above."
    var onOpen: (TaskItem) -> Void

    private let math = CalendarMath()

    /// Done tasks stay visible (struck through) for a day, then hide unless "Show Completed" is on.
    private var visible: [TaskItem] {
        let dayAgo = now.addingTimeInterval(-86_400)
        return allTasks.filter { task in
            if let area { guard task.area === area else { return false } }
            else if let taskArea = task.area, taskArea.semester?.isActive != true { return false }
            if task.isDone && hidesCompleted { return false }
            if task.isDone && !showCompleted { return (task.completedAt ?? .distantPast) > dayAgo }
            return true
        }
    }

    private var grouped: [(TaskBucket, [TaskItem])] {
        let groups = Dictionary(grouping: visible) { TaskBucket.bucket(due: $0.dueDate, hasTime: $0.dueHasTime, now: now, math: math) }
        return buckets.compactMap { bucket in
            guard let tasks = groups[bucket], !tasks.isEmpty else { return nil }
            return (bucket, tasks.sorted(by: Self.order))
        }
    }

    static func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.createdAt < b.createdAt
    }

    var isEmpty: Bool { grouped.isEmpty }

    var body: some View {
        if grouped.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(emptyTitle)
                Card {
                    CardRow(icon: "checkmark.circle") {
                        Text(emptyMessage).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ForEach(grouped, id: \.0) { bucket, tasks in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(bucket.title, detail: "\(tasks.filter { !$0.isDone }.count)")
                    Card {
                        ForEach(Array(tasks.enumerated()), id: \.element.liveID) { index, task in
                            if index > 0 { CardDivider(inset: Theme.Space.xl + Theme.Space.l) }
                            TaskRow(task: task, showsCourse: area == nil, onOpen: onOpen)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
