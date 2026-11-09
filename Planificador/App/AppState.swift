import Foundation
import Observation
import SwiftData

enum SidebarItem: Hashable {
    case today
    case calendar
    case tasks
    case area(PersistentIdentifier)
}

/// Xcode previews run with the app's bundle id, so anything they persist lands in the real app's
/// preferences and folders. Persistence and backups are skipped while previewing.
enum AppEnvironment {
    static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

@Observable
final class AppState {
    var selection: SidebarItem? = .calendar

    // Calendar
    var calendarMode: CalendarMode {
        didSet { if !AppEnvironment.isPreview { UserDefaults.standard.set(calendarMode.rawValue, forKey: "calendarMode") } }
    }
    var calendarAnchor = Date.now

    /// Start of the current day. The main window is keyed on it, so a Mac that slept past midnight redraws for the new day.
    private(set) var today = Calendar.autoupdatingCurrent.startOfDay(for: .now)

    func refreshDay() {
        let calendar = Calendar.autoupdatingCurrent
        let now = calendar.startOfDay(for: .now)
        guard now != today else { return }
        // The calendar was showing "today": follow the new day instead of staying on the old one.
        if calendar.isDate(calendarAnchor, inSameDayAs: today) { calendarAnchor = .now }
        today = now
    }

    /// Menu commands are handed to the views that own the model context.
    var pendingCommand: AppCommand?

    /// Root that holds the semester folders, e.g. `~/Documents/PUJ/Classes`.
    var classesRootPath: String {
        didSet { if !AppEnvironment.isPreview { UserDefaults.standard.set(classesRootPath, forKey: Self.rootKey) } }
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

/// Actions triggered from the menu bar.
enum AppCommand: Equatable {
    case newTask
    case newEvent
    case exportBackup
    case importBackup
    case backUpNow
    case calendarPrevious
    case calendarNext
    case calendarToday
}
