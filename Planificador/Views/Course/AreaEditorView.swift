import AgendaCore
import SwiftData
import SwiftUI

/// Create a personal area (no folder) or edit a course's name, tag and color.
struct AreaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let area: Area?
    let semester: Semester?

    @State private var name = ""
    @State private var tag = ""
    @State private var colorHex = CoursePalette.color(at: 0)
    @State private var triedToSave = false

    var body: some View {
        SheetScaffold(eyebrow: area == nil ? "New Personal Area" : "Edit Course") {
            HStack(spacing: Theme.Space.m) {
                AreaBadge(name: name.isEmpty ? "?" : name, colorHex: colorHex)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.editorTitle)
                    .onChange(of: name) {
                        if area == nil { tag = TagSuggester.suggest(for: name, existing: takenTags) }
                    }
            }

            Card {
                CardRow(icon: "number") {
                    Text("Tag")
                    Spacer()
                    TextField("tag", text: $tag)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.Font.tag)
                        .frame(width: 140)
                        .onChange(of: tag) { tag = TagSuggester.normalize(tag) }
                }
                CardDivider()
                CardRow(icon: "paintpalette") {
                    ColorSwatchPicker(hex: $colorHex)
                }
            }

            if area == nil {
                Text("For things that aren’t courses: `#personal`, `#work`, `#gym`…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }

            if let problem, triedToSave || takenTags.contains(tag) {
                ValidationMessage(text: problem)
            }
        } footer: {
            ActionBar(
                destructiveTitle: area?.folderPath == nil && area != nil ? "Archive" : nil,
                onDestructive: {
                    area?.isArchived = true
                    dismiss()
                },
                onCancel: { dismiss() },
                primaryTitle: area == nil ? "Create" : "Save",
                onPrimary: {
                    triedToSave = true
                    if problem == nil { save() }
                })
        }
        .onAppear {
            if let area {
                name = area.name
                tag = area.tag
                colorHex = area.colorHex
            } else {
                colorHex = CoursePalette.color(at: semester?.areas.count ?? 0)
            }
        }
    }

    private var takenTags: Set<String> {
        Set((semester?.areas ?? []).filter { $0 !== area && !$0.isArchived }.map(\.tag))
    }

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a name." }
        if tag.isEmpty { return "Enter a tag." }
        if takenTags.contains(tag) { return "Another course already uses #\(tag)." }
        return nil
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        if let area {
            area.name = cleanName
            area.tag = tag
            area.colorHex = colorHex
        } else {
            let order = (semester?.areas.map(\.sortOrder).max() ?? -1) + 1
            context.insert(Area(name: cleanName, tag: tag, colorHex: colorHex, folderPath: nil, semester: semester, sortOrder: order))
        }
        try? context.save()
        dismiss()
    }
}
