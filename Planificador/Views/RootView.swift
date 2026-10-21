import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Semester> { $0.isActive }) private var activeSemesters: [Semester]

    var body: some View {
        if let semester = activeSemesters.first {
            MainSplitView(semester: semester)
                .task(id: semester.persistentModelID) { semester.normalizeDates() }
        } else {
            SetupWizardView()
        }
    }
}

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    let semester: Semester

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(semester: semester)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selection {
        case .today:
            PlaceholderView(title: "Hoy", systemImage: "sun.max", message: "Tus tareas vencidas, las de hoy y tus bloques del día aparecerán aquí (fase 3).")
        case .week, .none:
            PlaceholderView(title: "Semana", systemImage: "calendar", message: "El calendario semanal llega en la fase 2.")
        case .tasks:
            PlaceholderView(title: "Tareas", systemImage: "checklist", message: "Las tareas con entrada rápida llegan en la fase 3.")
        case .area(let id):
            if let area = context.model(for: id) as? Area, area.semester != nil {
                CourseView(area: area)
                    .id(id)
            } else {
                PlaceholderView(title: "Materia", systemImage: "questionmark.folder", message: "Esta materia ya no existe.")
            }
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .navigationTitle(title)
    }
}
