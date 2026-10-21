import AppKit
import SwiftData
import SwiftUI

enum CourseTab: String, CaseIterable, Identifiable {
    case tasks = "Tareas"
    case notes = "Notas"
    case files = "Archivos"
    case schedule = "Horario"

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
                    PlaceholderView(title: "Tareas", systemImage: "checklist", message: "Las tareas de #\(area.tag) llegan en la fase 3.")
                case .notes:
                    PlaceholderView(title: "Notas", systemImage: "note.text", message: "Las notas en Markdown llegan en la fase 4.")
                case .files:
                    PlaceholderView(title: "Archivos", systemImage: "folder", message: "El explorador de archivos llega en la fase 4.")
                case .schedule:
                    PlaceholderView(title: "Horario", systemImage: "clock", message: "El horario de clases llega en la fase 2.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(area.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sección", selection: $tab) {
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
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: area.colorHex).gradient)
                .frame(width: 42, height: 42)
                .overlay {
                    Text(String(area.name.prefix(1)))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(area.name).font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text("#\(area.tag)").font(.callout.monospaced()).foregroundStyle(.secondary)
                    if let url = area.folderURL, !area.isFolderMissing {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder")
                                .font(.callout)
                        }
                        .buttonStyle(.link)
                        .help(url.path(percentEncoded: false))
                    }
                }
            }
            Spacer()
            Button("Editar", systemImage: "pencil") { editing = true }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

/// Shown when a course folder was renamed or moved; lets the user point to it again.
struct MissingFolderBanner: View {
    @Bindable var area: Area

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("No encuentro la carpeta de esta materia").font(.callout.weight(.semibold))
                Text(area.folderPath ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Volver a vincular…") {
                let start = area.semester.map { URL(filePath: $0.folderPath, directoryHint: .isDirectory) }
                if let url = chooseFolder(startingAt: start, prompt: "Vincular") {
                    area.folderPath = url.path(percentEncoded: false)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}
