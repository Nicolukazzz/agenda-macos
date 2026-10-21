import AgendaCore
import AppKit
import SwiftUI

/// Edits one Markdown file. Files outside `Notas/` open read-only until "Edit File" is pressed,
/// so course documents like CLAUDE.md can't be changed by accident. Autosaves 1 s after typing stops (atomic write). If the file changes on disk
/// (Claude Code, Obsidian…), it reloads; with unsaved edits it asks instead of overwriting anything.
struct NoteEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case edit = "Edit", split = "Split", preview = "Preview"
        var id: Self { self }
    }

    let url: URL
    let files: CourseFiles

    @State private var unlocked: Bool
    @AppStorage("noteEditorMode") private var mode: Mode = .split
    @State private var text: String
    @State private var savedText: String
    @State private var savedDate: Date?
    @State private var watcher: FileWatcher?
    @State private var saveTask: Task<Void, Never>?
    @State private var conflict = false
    @State private var confirmingTrash = false
    @State private var saveError: String?

    init(url: URL, files: CourseFiles, isNote: Bool) {
        self.url = url
        self.files = files
        _unlocked = State(initialValue: isNote)
        let contents = CourseFiles.read(url) ?? ""
        _text = State(initialValue: contents)
        _savedText = State(initialValue: contents)
        _savedDate = State(initialValue: CourseFiles.modificationDate(url))
    }

    private var isDirty: Bool { text != savedText }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if unlocked && mode != .preview { editor }
                if unlocked && mode == .split { Divider() }
                if !unlocked || mode != .edit {
                    ScrollView {
                        MarkdownPreview(source: text)
                            .padding(Theme.Space.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            watcher = FileWatcher(url: url) { externalChange() }
        }
        .onDisappear {
            saveTask?.cancel()
            save()
        }
        .onChange(of: text) { scheduleSave() }
        .alert("This note changed on disk", isPresented: $conflict) {
            Button("Keep Mine") { overwrite() }
            Button("Use the Disk Version") { reloadFromDisk() }
            Button("Save Both") { saveBoth() }
        } message: {
            Text("Another app edited “\(url.lastPathComponent)” while you had unsaved changes.")
        }
        .confirmationDialog("Move “\(url.lastPathComponent)” to the Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                Task { try? await files.trash(url) }
            }
        } message: {
            Text("You can restore it from the Trash.")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(NoteNaming.displayTitle(fileName: url.lastPathComponent, contents: text))
                    .font(Theme.Font.sectionTitle)
                    .lineLimit(1)
                Text(status).font(Theme.Font.caption).foregroundStyle(saveError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.Palette.danger))
            }
            Spacer()
            if unlocked {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                Button("Edit File", systemImage: "lock.open") { withAnimation(Theme.Motion.snappy) { unlocked = true } }
                    .buttonStyle(.glass)
                    .help("This file isn’t in Notas/. Unlock to edit it.")
            }
            Button("Toggle Preview") { mode = mode == .edit ? .split : (mode == .split ? .preview : .edit) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .hidden()
                .frame(width: 0)
            IconButton(title: "Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            IconButton(title: "Move to Trash", systemImage: "trash", role: .destructive) { confirmingTrash = true }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var status: String {
        if let saveError { return saveError }
        if !unlocked { return "Read-only · \(url.lastPathComponent)" }
        if isDirty { return "Editing…" }
        return "Saved · \(url.lastPathComponent)"
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard isDirty else { return }
        // Someone else wrote the file since we loaded it: don't overwrite silently.
        if let disk = CourseFiles.modificationDate(url), let savedDate, disk > savedDate.addingTimeInterval(0.5),
           CourseFiles.read(url) != savedText {
            conflict = true
            return
        }
        write(text, to: url)
    }

    private func write(_ contents: String, to target: URL) {
        do {
            try CourseFiles.write(contents, to: target)
            if target == url {
                savedText = contents
                savedDate = CourseFiles.modificationDate(url)
            }
            saveError = nil
        } catch {
            saveError = "Couldn’t save: \(error.localizedDescription)"
        }
    }

    private func externalChange() {
        guard let disk = CourseFiles.read(url) else { return }
        guard disk != savedText else { return }
        if isDirty {
            conflict = true
        } else {
            reloadFromDisk()
        }
    }

    private func reloadFromDisk() {
        let disk = CourseFiles.read(url) ?? ""
        savedText = disk
        text = disk
        savedDate = CourseFiles.modificationDate(url)
    }

    private func overwrite() {
        savedDate = CourseFiles.modificationDate(url)
        write(text, to: url)
    }

    /// Keeps the disk version in place and writes our version next to it as "… (conflict).md".
    private func saveBoth() {
        let base = url.deletingPathExtension().lastPathComponent
        let copy = url.deletingLastPathComponent().appending(path: "\(base) (conflict).md")
        write(text, to: copy)
        reloadFromDisk()
        files.reload()
    }
}
