import AgendaCore
import SwiftUI

/// A course's notes: list on the left (its `Notas/` notes plus other Markdown files), editor on the right.
struct NotesView: View {
    let files: CourseFiles

    @State private var selection: URL?
    @State private var search = ""
    @State private var creating = false
    @State private var newTitle = ""
    @State private var error: String?

    private func matches(_ note: NoteFile) -> Bool {
        search.isEmpty || note.title.localizedStandardContains(search) || note.url.lastPathComponent.localizedStandardContains(search)
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 280)
            Divider()
            Group {
                if let selection, FileManager.default.fileExists(atPath: selection.path(percentEncoded: false)) {
                    NoteEditorView(url: selection, files: files, isNote: files.notes.contains { $0.url == selection })
                        .id(selection)
                } else {
                    EmptyState(title: "No Note Selected", systemImage: "note.text", message: "Pick a note or create one. Notes are saved as Markdown in this course’s Notas folder.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? files.notes.first?.url }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                SearchField(text: $search, prompt: "Search notes")
                IconButton(title: "New Note", systemImage: "square.and.pencil") { creating = true }
                    .popover(isPresented: $creating, arrowEdge: .bottom) { newNotePopover }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    section("Notes", files.notes.filter(matches), empty: "No notes yet.")
                    if !files.otherDocuments.filter(matches).isEmpty {
                        section("Other Documents", files.otherDocuments.filter(matches), empty: "")
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(Theme.Space.m)
    }

    private func section(_ title: String, _ notes: [NoteFile], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title, detail: notes.isEmpty ? nil : "\(notes.count)")
            if notes.isEmpty {
                Text(empty).font(Theme.Font.caption).foregroundStyle(.secondary).padding(.horizontal, Theme.Space.xs)
            }
            ForEach(notes) { note in
                NoteListRow(note: note, isSelected: selection == note.url) { selection = note.url }
            }
        }
    }

    private var newNotePopover: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New Note").font(Theme.Font.sectionTitle)
            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(create)
            if let error { ValidationMessage(text: error) }
            HStack {
                Spacer()
                Button("Create", action: create)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.l)
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        do {
            selection = try files.createNote(title: title)
            newTitle = ""
            error = nil
            creating = false
        } catch {
            self.error = "Couldn’t create the note: \(error.localizedDescription)"
        }
    }
}

private struct NoteListRow: View {
    let note: NoteFile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(note.title).font(Theme.Font.rowTitle.weight(.medium)).lineLimit(1)
                Text(note.isNote ? note.modified.agenda(.dateTime.day().month(.abbreviated).hour().minute()) : note.url.deletingLastPathComponent().lastPathComponent)
                    .font(Theme.Font.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(inset: 0)
        .help(note.url.path(percentEncoded: false))
    }
}
