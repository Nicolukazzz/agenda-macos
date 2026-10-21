import AppKit
import SwiftData
import SwiftUI

enum CourseTab: String, CaseIterable, Identifiable {
    case tasks = "Tasks"
    case notes = "Notes"
    case files = "Files"
    case schedule = "Schedule"

    var id: Self { self }
}

struct CourseView: View {
    @Bindable var area: Area
    @State private var tab: CourseTab = .tasks
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if area.isFolderMissing {
                MissingFolderBanner(area: area)
            }
            Divider()
            Group {
                switch tab {
                case .tasks:
                    CourseTasksView(area: area)
                case .notes:
                    EmptyState(title: "Notes", systemImage: "note.text", message: "Markdown notes arrive in phase 4.")
                case .files:
                    EmptyState(title: "Files", systemImage: "folder", message: "The file browser arrives in phase 4.")
                case .schedule:
                    ScheduleView(area: area)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(area.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    ForEach(CourseTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .sheet(isPresented: $editing) {
            AreaEditorView(area: area, semester: area.semester)
        }
    }

    private var header: some View {
        PageHeader(title: area.name) {
            AreaBadge(name: area.name, colorHex: area.colorHex)
        } trailing: {
            TagPill(tag: area.tag, colorHex: area.colorHex)
            if let url = area.folderURL, !area.isFolderMissing {
                IconButton(title: "Open Folder in Finder", systemImage: "folder") { NSWorkspace.shared.open(url) }
            }
            IconButton(title: "Edit Course", systemImage: "pencil") { editing = true }
        }
    }
}

/// Shown when a course folder was renamed or moved; lets the user point to it again.
struct MissingFolderBanner: View {
    @Bindable var area: Area

    var body: some View {
        Banner(title: "This course’s folder can’t be found", message: area.folderPath) {
            Button("Relink…") {
                let start = area.semester.map { URL(filePath: $0.folderPath, directoryHint: .isDirectory) }
                if let url = chooseFolder(startingAt: start, prompt: "Relink") {
                    area.folderPath = url.path(percentEncoded: false)
                }
            }
            .buttonStyle(.glass)
        }
    }
}

/// A course's tasks with quick add prefilled to the course.
struct CourseTasksView: View {
    let area: Area
    @State private var editing: TaskItem?

    var body: some View {
        PageContent {
            QuickAddBar(areas: area.semester?.sortedAreas ?? [area], defaultArea: area)
            TaskListView(area: area) { editing = $0 }
        }
        .sheet(item: $editing) { task in
            if let semester = area.semester { TaskEditorView(task: task, semester: semester) }
        }
    }
}
