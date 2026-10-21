import AgendaCore
import SwiftData
import SwiftUI

/// All tasks of the semester, with quick add and a course filter.
struct TasksPage: View {
    let semester: Semester

    @State private var filter: Area?
    @State private var showCompleted = false
    @State private var editing: TaskItem?

    var body: some View {
        PageContent {
            QuickAddBar(areas: semester.sortedAreas, defaultArea: filter)
            CourseChips(selection: $filter, areas: semester.sortedAreas, noneTitle: "All")
            TaskListView(area: filter, showCompleted: showCompleted) { editing = $0 }
        }
        .navigationTitle("Tasks")
        .navigationSubtitle("Semester \(semester.name)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showCompleted.animation(Theme.Motion.snappy)) {
                    Label("Show Completed", systemImage: "checkmark.circle")
                }
                .help("Show completed tasks")
            }
        }
        .sheet(item: $editing) { TaskEditorView(task: $0, semester: semester) }
    }
}
