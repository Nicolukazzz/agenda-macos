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
        return container
    }()

    static var firstArea: Area {
        try! container.mainContext.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.sortOrder)])).first!
    }
}

#Preview("Main") {
    RootView()
        .environment(AppState())
        .modelContainer(PreviewData.container)
        .frame(width: 1100, height: 700)
}

#Preview("Wizard") {
    SetupWizardView()
        .environment(AppState())
        .modelContainer(PreviewData.container)
}
