import AgendaCore
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    let semester: Semester

    @State private var showingSemesterSettings = false
    @State private var showingNewArea = false
    @State private var showingNewSemester = false

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selection) {
            Section("Planner") {
                Label("Today", systemImage: "sun.max").tag(SidebarItem.today)
                Label("Calendar", systemImage: "calendar").tag(SidebarItem.calendar)
                Label("Tasks", systemImage: "checklist").tag(SidebarItem.tasks)
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
