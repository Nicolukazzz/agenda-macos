import AgendaCore
import AppKit
import Foundation
import Observation

/// A Markdown file shown in a course's Notes tab.
struct NoteFile: Identifiable, Hashable {
    let url: URL
    let title: String
    let modified: Date
    /// True for files in `<course>/Notas/`; false for other `.md` files of the course (e.g. CLAUDE.md).
    let isNote: Bool

    var id: URL { url }
}

/// A file or folder in a course's Files tab.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Reads a course folder for the Notes and Files tabs. The only writes it ever makes are
/// inside `<course>/Notas/`; deleting a note moves it to the Trash.
@MainActor
@Observable
final class CourseFiles {
    let folder: URL
    private(set) var notes: [NoteFile] = []
    private(set) var otherDocuments: [NoteFile] = []
    private(set) var tree: [FileNode] = []

    @ObservationIgnored private var watchers: [FileWatcher] = []

    /// Folders that are never worth browsing.
    private static let skipped: Set<String> = ["node_modules", ".git", ".build", "build", "DerivedData", "__pycache__", ".venv"]
    private static let maxDepth = 6

    var notesFolder: URL { folder.appending(path: NoteNaming.notesFolderName, directoryHint: .isDirectory) }

    init(folder: URL) {
        self.folder = folder
        reload()
        watch()
    }

    func reload() {
        tree = Self.scan(folder, depth: 0)
        let markdown = Self.flatten(tree).filter { !$0.isFolder && $0.url.pathExtension.lowercased() == "md" }
        let notesPath = notesFolder.standardizedFileURL.path(percentEncoded: false)
        let notesPrefix = notesPath.hasSuffix("/") ? notesPath : notesPath + "/"
        let files = markdown.map { node in
            let isNote = node.url.standardizedFileURL.path(percentEncoded: false).hasPrefix(notesPrefix)
            return NoteFile(
                url: node.url,
                title: NoteNaming.displayTitle(fileName: node.name, contents: Self.head(of: node.url)),
                modified: (try? node.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
                isNote: isNote)
        }
        notes = files.filter(\.isNote).sorted { $0.modified > $1.modified }
        otherDocuments = files.filter { !$0.isNote }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Re-arms watchers on the course folder and `Notas/` (if it exists).
    private func watch() {
        watchers = [folder, notesFolder]
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .map { FileWatcher(url: $0) { [weak self] in self?.reload() } }
    }

    // MARK: Notes

    func createNote(title: String) throws -> URL {
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        let name = NoteNaming.fileName(title: title, date: .now) { candidate in
            FileManager.default.fileExists(atPath: self.notesFolder.appending(path: candidate).path(percentEncoded: false))
        }
        let url = notesFolder.appending(path: name)
        try Data(NoteNaming.template(title: title).utf8).write(to: url, options: .atomic)
        reload()
        watch()
        return url
    }

    static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
    }

    /// Moves a note to the Trash (recoverable), never deletes it.
    func trash(_ url: URL) async throws {
        _ = try await NSWorkspace.shared.recycle([url])
        reload()
    }

    // MARK: Scanning

    private static func scan(_ url: URL, depth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { !skipped.contains($0.lastPathComponent) }
            .map { item in
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                let isFolder = values?.isDirectory == true && values?.isPackage != true
                return FileNode(url: item, isFolder: isFolder, children: isFolder ? scan(item, depth: depth + 1) : nil)
            }
            .sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func flatten(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { [$0] + flatten($0.children ?? []) }
    }

    /// First ~1 KB of a file, enough to find its `# Title`.
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1024)).flatMap { String(decoding: $0, as: UTF8.self) }
    }
}
