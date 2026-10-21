import Foundation
import Observation
import SwiftData

enum SidebarItem: Hashable {
    case today
    case week
    case tasks
    case area(PersistentIdentifier)
}

@Observable
final class AppState {
    var selection: SidebarItem? = .week

    /// Root that holds the semester folders, e.g. `~/Documents/PUJ/Classes`.
    var classesRootPath: String {
        didSet { UserDefaults.standard.set(classesRootPath, forKey: Self.rootKey) }
    }

    private static let rootKey = "classesRootPath"
    static let defaultRootPath = URL.documentsDirectory.appending(path: "PUJ/Classes").path(percentEncoded: false)

    init() {
        classesRootPath = UserDefaults.standard.string(forKey: Self.rootKey) ?? Self.defaultRootPath
    }

    var classesRootURL: URL {
        URL(filePath: classesRootPath, directoryHint: .isDirectory)
    }
}
