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
    /// Folder contents for the Notes and Files tabs; rebuilt when the course is relinked.
    @State private var files: CourseFiles?

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
                    if let files { NotesView(files: files) } else { noFolder }
                case .files:
                    if let files { FilesView(files: files) } else { noFolder }
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
        .task(id: area.folderPath) {
            files = area.isFolderMissing ? nil : area.folderURL.map(CourseFiles.init(folder:))
        }
        .sheet(isPresented: $editing) {
            AreaEditorView(area: area, semester: area.semester)
        }
    }

    private var noFolder: some View {
        EmptyState(
            title: area.folderPath == nil ? "No Folder" : "Folder Not Found",
            systemImage: "questionmark.folder",
            message: area.folderPath == nil ? "Personal areas don’t have a folder." : "Relink the course folder to see its notes and files.")
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
