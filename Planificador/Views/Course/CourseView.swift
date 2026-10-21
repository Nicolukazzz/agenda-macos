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
                    PlaceholderView(title: "Tasks", systemImage: "checklist", message: "Tasks for #\(area.tag) arrive in phase 3.")
                case .notes:
                    PlaceholderView(title: "Notes", systemImage: "note.text", message: "Markdown notes arrive in phase 4.")
                case .files:
                    PlaceholderView(title: "Files", systemImage: "folder", message: "The file browser arrives in phase 4.")
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
            HStack(spacing: Theme.Space.s) {
                TagPill(tag: area.tag, colorHex: area.colorHex)
                if let url = area.folderURL, !area.isFolderMissing {
                    Button("Open Folder", systemImage: "folder") { NSWorkspace.shared.open(url) }
                        .help(url.path(percentEncoded: false))
                }
                Button("Edit", systemImage: "pencil") { editing = true }
            }
            .buttonStyle(.glass)
        }
    }
}

/// Shown when a course folder was renamed or moved; lets the user point to it again.
struct MissingFolderBanner: View {
    @Bindable var area: Area

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This course’s folder can’t be found").font(.callout.weight(.semibold))
                Text(area.folderPath ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Relink…") {
                let start = area.semester.map { URL(filePath: $0.folderPath, directoryHint: .isDirectory) }
                if let url = chooseFolder(startingAt: start, prompt: "Relink") {
                    area.folderPath = url.path(percentEncoded: false)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}
