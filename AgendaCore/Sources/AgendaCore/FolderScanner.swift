import Foundation

/// A semester folder such as `2026-2` inside the classes root.
public struct SemesterFolder: Equatable, Sendable {
    public let name: String
    public let url: URL
}

/// A class (course) folder inside a semester folder.
public struct CourseFolder: Equatable, Sendable {
    public let name: String
    public let url: URL
}

/// Reads the user's classes layout: `<root>/<AAAA-N>/<Materia>/`. Never writes.
public enum FolderScanner {
    /// Semester folder names look like `2026-2`.
    public static func isSemesterName(_ name: String) -> Bool {
        name.wholeMatch(of: /\d{4}-\d{1,2}/) != nil
    }

    /// Semester folders, newest first.
    public static func semesters(in root: URL, fileManager: FileManager = .default) throws -> [SemesterFolder] {
        try subdirectories(of: root, fileManager: fileManager)
            .filter { isSemesterName($0.lastPathComponent) }
            .map { SemesterFolder(name: $0.lastPathComponent, url: $0) }
            .sorted { compareSemester($0.name, $1.name) }
    }

    /// Course folders of a semester, sorted by name the way Finder does.
    public static func courses(in semester: URL, fileManager: FileManager = .default) throws -> [CourseFolder] {
        try subdirectories(of: semester, fileManager: fileManager)
            .map { CourseFolder(name: $0.lastPathComponent, url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Next semester name after `name`: `2026-2` → `2027-1`.
    public static func nextSemesterName(after name: String) -> String? {
        let parts = name.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[1] >= 2 ? "\(parts[0] + 1)-1" : "\(parts[0])-\(parts[1] + 1)"
    }

    private static func compareSemester(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.split(separator: "-").compactMap { Int($0) }
        let r = rhs.split(separator: "-").compactMap { Int($0) }
        return r.lexicographicallyPrecedes(l) // newest first
    }

    private static func subdirectories(of url: URL, fileManager: FileManager) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { item in
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }
    }
}
