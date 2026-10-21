import AgendaCore
import SwiftData
import SwiftUI

/// In-memory sample data for SwiftUI previews only.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema(AgendaSchema.models)
        let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let semester = Semester(
            name: "2026-2", folderPath: "/tmp/2026-2",
            startDate: .now.addingTimeInterval(-60 * 86_400), endDate: .now.addingTimeInterval(40 * 86_400))
        context.insert(semester)
        let courses = [("BD", "bd"), ("Sistemas Operativos", "so"), ("Gestión TI", "gti"), ("Teoria de la Computacion", "tc")]
        for (index, course) in courses.enumerated() {
            context.insert(Area(
                name: course.0, tag: course.1, colorHex: CoursePalette.color(at: index),
                folderPath: "/tmp/2026-2/\(course.0)", semester: semester, sortOrder: index))
        }
        let areas = try! context.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.sortOrder)]))
        let math = CalendarMath()
        let today = math.startOfDay(.now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            math.date(math.add(days: dayOffset, to: today), atMinutes: hour * 60 + minute)
        }
        let anchor = semester.startDate
        let classes: [(Int, Set<Int>, Int, Int, String)] = [
            (0, [2, 4], 7, 9, "Lab 302"), (1, [3, 5], 9, 11, "Aula 12"), (2, [2], 14, 16, ""), (3, [4, 6], 11, 13, "Edif. 67"),
        ]
        for (index, days, from, to, room) in classes {
            context.insert(Block(
                title: areas[index].name,
                start: math.date(anchor, atMinutes: from * 60), end: math.date(anchor, atMinutes: to * 60),
                area: areas[index], recurrence: WeeklyRecurrence(weekdays: days, until: semester.endDate), location: room))
        }
        context.insert(Block(title: "Doctor’s appointment", start: at(1, 8), end: at(1, 10)))
        context.insert(Block(title: "Study for midterm", start: at(2, 16), end: at(2, 18, 30), area: areas[0]))
        context.insert(TaskItem(title: "Project due", dueDate: at(2, 23, 59), area: areas[0], priority: 1))
        context.insert(TaskItem(title: "Threads lab", dueDate: at(4, 23, 59), area: areas[1]))
        context.insert(TaskItem(title: "Pitch Reserbox", dueDate: at(9, 18), dueHasTime: true, area: areas[2]))
        context.insert(TaskItem(title: "Automata quiz", dueDate: at(16, 10), dueHasTime: true, area: areas[3]))
        return container
    }()

    static let sampleClassesRoot: URL = {
        let root = FileManager.default.temporaryDirectory.appending(path: "agenda-preview-classes")
        for folder in ["2026-2/BD/Notas", "2026-2/BD/Presentaciones", "2026-2/BD/Talleres", "2026-2/Sistemas Operativos", "2026-2/Gestión TI", "2026-1/Calculo"] {
            try? FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        let files: [String: String] = [
            "2026-2/BD/Notas/2026-10-21 Normalización.md": "# Normalización\n\nUna tabla está en **3FN** si:\n\n- está en 2FN\n- no tiene dependencias *transitivas*\n\n> Cada atributo depende de la clave, toda la clave y nada más que la clave.\n\n```sql\nSELECT dept, COUNT(*)\n  FROM empleados\n GROUP BY dept;\n```\n\n| Forma | Regla |\n|---|---|\n| 1FN | atómicos |\n| 2FN | sin parciales |\n\n- [x] Leer capítulo 14\n- [ ] Taller 3\n",
            "2026-2/BD/Notas/2026-10-14 Joins.md": "# Joins y subconsultas\n\nINNER, LEFT, RIGHT.\n",
            "2026-2/BD/CLAUDE.md": "# Contexto de la materia\n\nBases de Datos.\n",
            "2026-2/BD/Presentaciones/1 - Introducción.pdf": "",
            "2026-2/BD/Talleres/Taller 3.sql": "SELECT 1;",
        ]
        for (path, contents) in files {
            try? Data(contents.utf8).write(to: root.appending(path: path))
        }
        return root
    }()

    static var sampleCourseFolder: URL { sampleClassesRoot.appending(path: "2026-2/BD", directoryHint: .isDirectory) }

    static var firstArea: Area {
        try! container.mainContext.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.sortOrder)])).first!
    }
}

#Preview("Month") {
    let state = AppState()
    state.calendarMode = .month
    return RootView()
        .environment(state)
        .modelContainer(PreviewData.container)
        .frame(width: 1200, height: 760)
}

#Preview("Week") {
    let state = AppState()
    state.calendarMode = .week
    return RootView()
        .environment(state)
        .modelContainer(PreviewData.container)
        .frame(width: 1200, height: 760)
}

#Preview("Wizard") {
    // Previews can't answer macOS's Documents-folder permission prompt, so they read a temporary sample layout.
    let state = AppState()
    state.classesRootPath = PreviewData.sampleClassesRoot.path(percentEncoded: false)
    return SetupWizardView()
        .environment(state)
        .modelContainer(PreviewData.container)
}

#Preview("Event editor") {
    let semester = try! PreviewData.container.mainContext.fetch(FetchDescriptor<Semester>()).first!
    let start = CalendarMath().date(.now, atMinutes: 9 * 60)
    return BlockEditorView(target: .new(start: start, end: start.addingTimeInterval(3600), area: nil), semester: semester)
        .modelContainer(PreviewData.container)
}

#Preview("Schedule") {
    ScheduleView(area: PreviewData.firstArea)
        .modelContainer(PreviewData.container)
        .frame(width: 760, height: 620)
}

#Preview("Tasks") {
    let state = AppState()
    state.selection = .tasks
    return RootView()
        .environment(state)
        .modelContainer(PreviewData.container)
        .frame(width: 1200, height: 760)
}

#Preview("Today") {
    let state = AppState()
    state.selection = .today
    return RootView()
        .environment(state)
        .modelContainer(PreviewData.container)
        .frame(width: 1200, height: 760)
}

#Preview("Task editor") {
    let context = PreviewData.container.mainContext
    let semester = try! context.fetch(FetchDescriptor<Semester>()).first!
    let task = try! context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)])).first!
    return TaskEditorView(task: task, semester: semester)
        .modelContainer(PreviewData.container)
}

#Preview("Notes") {
    NotesView(files: CourseFiles(folder: PreviewData.sampleCourseFolder))
        .frame(width: 1000, height: 700)
}

#Preview("Files") {
    FilesView(files: CourseFiles(folder: PreviewData.sampleCourseFolder))
        .frame(width: 900, height: 500)
}

#Preview("Settings") {
    AgendaSettingsView()
        .environment(AppState())
        .modelContainer(PreviewData.container)
}
