import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Semester> { $0.isActive }) private var activeSemesters: [Semester]

    var body: some View {
        if let semester = activeSemesters.first {
            MainSplitView(semester: semester)
                .task(id: semester.persistentModelID) {
                    semester.normalizeDates()
                    ScheduleImporter.importPending(into: semester, context: context)
                }
        } else {
            SetupWizardView()
        }
    }
}

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    let semester: Semester

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(semester: semester)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail
        }
        // ⌘Z / ⌘⇧Z undo calendar and task changes.
        .onAppear { context.undoManager = undoManager }
        .onChange(of: undoManager) { context.undoManager = undoManager }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selection {
        case .today:
            TodayView(semester: semester)
        case .calendar, .none:
            CalendarView(semester: semester)
        case .tasks:
            TasksPage(semester: semester)
        case .area(let id):
            if let area = context.model(for: id) as? Area, area.semester != nil {
                CourseView(area: area)
                    .id(id)
            } else {
                EmptyState(title: "Course", systemImage: "questionmark.folder", message: "This course no longer exists.")
            }
        }
    }
}
