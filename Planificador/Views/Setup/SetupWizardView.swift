import AgendaCore
import SwiftData
import SwiftUI

/// First-run (and new-semester) setup: pick the classes root, a semester folder, its dates and courses.
struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var semesters: [Semester]

    var onFinish: () -> Void = {}

    @State private var step = 0
    @State private var detected: [SemesterFolder] = []
    @State private var selectedSemester: String?
    @State private var drafts: [CourseDraft] = []
    @State private var scanError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case 0: rootStep
                default: coursesStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .onAppear(perform: scan)
    }

    // MARK: Header & footer

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(semesters.isEmpty ? "Bienvenido a Agenda" : "Nuevo semestre")
                    .font(.title2.weight(.semibold))
                Text(["Elige tu carpeta de clases", "Revisa tus materias"][step])
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Paso \(step + 1) de 2")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Atrás") { withAnimation(.smooth) { step -= 1 } }
            }
            Spacer()
            if step < 1 {
                Button("Siguiente") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 0 && selectedSemester == nil)
            } else {
                Button("Crear semestre") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draftsAreValid)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: Step 1 — root folder and semester

    private var rootStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Agenda lee tus carpetas de clases organizadas por semestre (por ejemplo `2026-2`). Nunca mueve ni borra tus archivos; solo crea la carpeta `Notas/` dentro de cada materia cuando escribas una nota.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Text(appState.classesRootPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Cambiar…") {
                    if let url = chooseFolder(startingAt: appState.classesRootURL, prompt: "Usar esta carpeta") {
                        appState.classesRootPath = url.path(percentEncoded: false)
                        scan()
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            if let scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if detected.isEmpty {
                Label("No encontré carpetas de semestre aquí (formato 2026-1 o 2026-2).", systemImage: "questionmark.folder")
                    .foregroundStyle(.secondary)
            } else {
                Text("Semestre a configurar").font(.headline)
                Picker("Semestre", selection: $selectedSemester) {
                    ForEach(detected, id: \.name) { folder in
                        Text(folder.name).tag(Optional(folder.name))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            Spacer()
        }
    }

    // MARK: Step 2 — courses

    private var coursesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cada carpeta es una materia. El tag es lo que escribirás con `#` para asignarle tareas (por ejemplo `Taller #so viernes`).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach($drafts) { $draft in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $draft.include).labelsHidden()
                        ColorMenu(hex: $draft.colorHex)
                        Text(draft.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(draft.include ? .primary : .secondary)
                        HStack(spacing: 2) {
                            Text("#").foregroundStyle(.secondary)
                            TextField("tag", text: $draft.tag)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                                .onChange(of: draft.tag) { draft.tag = TagSuggester.normalize(draft.tag) }
                        }
                        .disabled(!draft.include)
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.bordered)
            if let problem = draftProblem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
        }
    }

    // MARK: Logic

    private func scan() {
        do {
            detected = try FolderScanner.semesters(in: appState.classesRootURL)
                .filter { SemesterDates.range(for: $0.name) != nil }
            let configured = Set(semesters.map(\.name))
            selectedSemester = detected.first { !configured.contains($0.name) }?.name ?? detected.first?.name
            scanError = nil
        } catch {
            detected = []
            selectedSemester = nil
            scanError = "No pude leer la carpeta: \(error.localizedDescription)"
        }
    }

    private func advance() {
        if step == 0, let name = selectedSemester {
            loadDrafts(for: name)
        }
        withAnimation(.smooth) { step += 1 }
    }

    private func loadDrafts(for name: String) {
        guard let folder = detected.first(where: { $0.name == name }) else { return }
        var used: Set<String> = []
        drafts = ((try? FolderScanner.courses(in: folder.url)) ?? []).enumerated().map { index, course in
            let tag = TagSuggester.suggest(for: course.name, existing: used)
            used.insert(tag)
            return CourseDraft(name: course.name, url: course.url, tag: tag, colorHex: CoursePalette.color(at: index))
        }
    }

    private var draftProblem: String? {
        let tags = drafts.filter(\.include).map(\.tag)
        if tags.contains(where: \.isEmpty) { return "Cada materia necesita un tag." }
        if Set(tags).count != tags.count { return "Hay tags repetidos; cada materia necesita uno distinto." }
        return nil
    }

    private var draftsAreValid: Bool { draftProblem == nil }

    private func create() {
        guard
            let name = selectedSemester,
            let folder = detected.first(where: { $0.name == name }),
            let range = SemesterDates.range(for: name)
        else { return }
        for existing in semesters { existing.isActive = false }
        let semester = Semester(
            name: name,
            folderPath: folder.url.path(percentEncoded: false),
            startDate: range.start,
            endDate: range.end
        )
        context.insert(semester)
        for (index, draft) in drafts.filter(\.include).enumerated() {
            let area = Area(
                name: draft.name, tag: draft.tag, colorHex: draft.colorHex,
                folderPath: draft.url.path(percentEncoded: false), semester: semester, sortOrder: index)
            context.insert(area)
        }
        try? context.save()
        appState.selection = .week
        onFinish()
    }
}

struct CourseDraft: Identifiable {
    let id = UUID()
    var name: String
    var url: URL
    var tag: String
    var colorHex: String
    var include = true
}

/// Color dot that opens the course palette.
struct ColorMenu: View {
    @Binding var hex: String

    var body: some View {
        Menu {
            ForEach(CoursePalette.hexColors, id: \.self) { color in
                Button {
                    hex = color
                } label: {
                    Label {
                        Text(color)
                    } icon: {
                        Image(nsImage: swatch(color))
                    }
                }
            }
        } label: {
            AreaDot(hex: hex, size: 14)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func swatch(_ hex: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(Color(hex: hex)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image
    }
}
