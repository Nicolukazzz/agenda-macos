import Foundation
import Observation
import SwiftData

enum SidebarItem: Hashable {
    case today
    case calendar
    case tasks
    case area(PersistentIdentifier)
}

@Observable
final class AppState {
    var selection: SidebarItem? = .calendar

    // Calendar
    var calendarMode: CalendarMode {
        didSet { UserDefaults.standard.set(calendarMode.rawValue, forKey: "calendarMode") }
    }
    var calendarAnchor = Date.now

    /// Root that holds the semester folders, e.g. `~/Documents/PUJ/Classes`.
    var classesRootPath: String {
        didSet { UserDefaults.standard.set(classesRootPath, forKey: Self.rootKey) }
    }

    private static let rootKey = "classesRootPath"
    static let defaultRootPath = URL.documentsDirectory.appending(path: "PUJ/Classes").path(percentEncoded: false)

    init() {
        let defaults = UserDefaults.standard
        classesRootPath = defaults.string(forKey: Self.rootKey) ?? Self.defaultRootPath
        calendarMode = defaults.string(forKey: "calendarMode").flatMap(CalendarMode.init(rawValue:)) ?? .month
    }

    var classesRootURL: URL {
        URL(filePath: classesRootPath, directoryHint: .isDirectory)
    }
}

/// Month is the main view; week is for detailed planning.
enum CalendarMode: String, CaseIterable, Identifiable {
    case month
    case week

    var id: Self { self }
    var title: String { self == .month ? "Month" : "Week" }
}
