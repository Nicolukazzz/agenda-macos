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
        VStack(alignment: .leading, spacing: 16) {
            Text(area == nil ? "New Personal Area" : "Edit \(area?.name ?? "")")
                .font(.title3.weight(.semibold))
            if area == nil {
                Text("For things that aren’t courses: `#personal`, `#work`, `#gym`…")
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("Name", text: $name)
                    .onChange(of: name) {
                        if area == nil { tag = TagSuggester.suggest(for: name, existing: takenTags) }
                    }
                HStack {
                    Text("#").foregroundStyle(.secondary)
                    TextField("Tag", text: $tag)
                        .onChange(of: tag) { tag = TagSuggester.normalize(tag) }
                }
                LabeledContent("Color") {
                    HStack(spacing: 6) {
                        ForEach(CoursePalette.hexColors, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                AreaDot(hex: hex, size: 18)
                                    .overlay {
                                        if hex == colorHex {
                                            Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 24, height: 24)
                                        }
                                    }
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            if let problem, triedToSave || takenTags.contains(tag) {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
            HStack {
                if let area, area.folderPath == nil {
                    Button("Archive", role: .destructive) {
                        area.isArchived = true
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(area == nil ? "Create" : "Save") {
                    triedToSave = true
                    if problem == nil { save() }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
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
