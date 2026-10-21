import AgendaCore
import SwiftData
import SwiftUI

/// First-run (and new-semester) setup: pick the classes root and semester, then review its courses.
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
            PageHeader(
                title: semesters.isEmpty ? "Welcome to Agenda" : "New Semester",
                subtitle: ["Choose your classes folder", "Review your courses"][step]
            ) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
            } trailing: {
                Text("Step \(step + 1) of 2").font(Theme.Font.rowDetail).foregroundStyle(.secondary)
            }
            Divider()
            PageContent {
                if step == 0 { rootStep } else { coursesStep }
            }
            Divider()
            footer
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.m)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear(perform: scan)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.s) {
            if step > 0 {
                Button("Back") { withAnimation(Theme.Motion.standard) { step -= 1 } }
                    .secondaryAction()
            }
            Spacer()
            if step == 0 {
                Button("Next") { advance() }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedSemester == nil)
            } else {
                Button("Create Semester") { create() }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draftsAreValid)
            }
        }
    }

    // MARK: Step 1 — root folder and semester

    @ViewBuilder
    private var rootStep: some View {
        Text("Agenda reads your classes folders, organized by semester (for example `2026-2`). It never moves or deletes your files; it only creates a `Notas/` folder inside a course when you write a note.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Card {
            CardRow(icon: "folder.fill", iconColor: .accentColor) {
                Text(appState.classesRootPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Change…") {
                    if let url = chooseFolder(startingAt: appState.classesRootURL, prompt: "Use This Folder") {
                        appState.classesRootPath = url.path(percentEncoded: false)
                        scan()
                    }
                }
                .buttonStyle(.glass)
            }
        }

        if let scanError {
            ValidationMessage(text: scanError)
        } else if detected.isEmpty {
            EmptyState(title: "No Semester Folders", systemImage: "questionmark.folder", message: "Folders must be named like 2026-1 or 2026-2.")
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader("Semester")
                Card {
                    ForEach(Array(detected.enumerated()), id: \.element.name) { index, folder in
                        if index > 0 { CardDivider() }
                        CardRow(icon: selectedSemester == folder.name ? "checkmark.circle.fill" : "circle",
                                iconColor: selectedSemester == folder.name ? .accentColor : .secondary) {
                            Text(folder.name).font(Theme.Font.rowTitle.monospacedDigit())
                            Spacer()
                            if semesters.contains(where: { $0.name == folder.name }) {
                                Text("Already set up").font(Theme.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedSemester = folder.name }
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }

    // MARK: Step 2 — courses

    @ViewBuilder
    private var coursesStep: some View {
        Text("Each folder is a course. Its tag is what you’ll type after `#` to assign tasks and events (for example `Lab report #so friday`).")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Card {
            ForEach(Array($drafts.enumerated()), id: \.element.id) { index, $draft in
                if index > 0 { CardDivider(inset: Theme.Space.m + 2) }
                CardRow {
                    Toggle("Include \(draft.name)", isOn: $draft.include)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    ColorSwatchMenu(hex: $draft.colorHex)
                    Text(draft.name)
                        .foregroundStyle(draft.include ? .primary : .secondary)
                    Spacer()
                    Text("#").foregroundStyle(.secondary)
                    TextField("tag", text: $draft.tag)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.tag)
                        .frame(width: 100)
                        .onChange(of: draft.tag) { draft.tag = TagSuggester.normalize(draft.tag) }
                        .disabled(!draft.include)
                }
            }
        }

        if let problem = draftProblem {
            ValidationMessage(text: problem)
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
            scanError = "Couldn’t read the folder: \(error.localizedDescription)"
        }
    }

    private func advance() {
        if step == 0, let name = selectedSemester {
            loadDrafts(for: name)
        }
        withAnimation(Theme.Motion.standard) { step += 1 }
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
        if tags.contains(where: \.isEmpty) { return "Every course needs a tag." }
        if Set(tags).count != tags.count { return "Tags must be unique; two courses share one." }
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
        appState.selection = .calendar
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
