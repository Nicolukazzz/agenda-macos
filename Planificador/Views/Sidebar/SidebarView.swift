import AgendaCore
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    let semester: Semester

    @Query(filter: #Predicate<TaskItem> { !$0.isDone && $0.dueDate != nil }) private var openTasks: [TaskItem]

    @State private var showingSemesterSettings = false
    @State private var showingNewArea = false
    @State private var showingNewSemester = false

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selection) {
            Section("Planner") {
                // `.tag` must stay outermost: applied before `.badge`, the row can't be selected.
                Label("Today", systemImage: "sun.max")
                    .badge(pendingToday)
                    .tag(SidebarItem.today)
                Label("Calendar", systemImage: "calendar").tag(SidebarItem.calendar)
                Label("Tasks", systemImage: "checklist").tag(SidebarItem.tasks)
                Label("Money", systemImage: "banknote").tag(SidebarItem.money)
            }

            Section {
                ForEach(semester.sortedAreas) { area in
                    AreaRow(area: area).tag(SidebarItem.area(area.persistentModelID))
                }
            } header: {
                HStack {
                    Text("Semester \(semester.name)")
                    Spacer()
                    Menu {
                        Button("Add Personal Area…", systemImage: "plus") { showingNewArea = true }
                        Button("Semester Settings…", systemImage: "calendar.badge.clock") { showingSemesterSettings = true }
                        Divider()
                        Button("New Semester…", systemImage: "folder.badge.plus") { showingNewSemester = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .large)
        .sheet(isPresented: $showingSemesterSettings) {
            SemesterSettingsView(semester: semester)
        }
        .sheet(isPresented: $showingNewArea) {
            AreaEditorView(area: nil, semester: semester)
        }
        .sheet(isPresented: $showingNewSemester) {
            SetupWizardView { showingNewSemester = false }
        }
    }

    /// Overdue + due today, shown as the Today badge.
    private var pendingToday: Int {
        let math = CalendarMath()
        return openTasks.filter {
            let bucket = TaskBucket.bucket(due: $0.dueDate, hasTime: $0.dueHasTime, now: .now, math: math)
            return bucket == .overdue || bucket == .today
        }.count
    }
}

struct AreaRow: View {
    let area: Area

    var body: some View {
        HStack(spacing: 8) {
            AreaDot(hex: area.colorHex)
            Text(area.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if area.isFolderMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This course’s folder can’t be found")
            }
            Text("#\(area.tag)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
