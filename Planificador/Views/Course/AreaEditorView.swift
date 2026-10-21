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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(area == nil ? "Nueva área personal" : "Editar \(area?.name ?? "")")
                .font(.title3.weight(.semibold))
            if area == nil {
                Text("Para cosas que no son materias: `#personal`, `#trabajo`, `#gym`…")
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("Nombre", text: $name)
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
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
            HStack {
                if let area, area.folderPath == nil {
                    Button("Archivar", role: .destructive) {
                        area.isArchived = true
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(area == nil ? "Crear" : "Guardar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
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
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Escribe un nombre." }
        if tag.isEmpty { return "Escribe un tag." }
        if takenTags.contains(tag) { return "Ya hay otra materia con #\(tag)." }
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
