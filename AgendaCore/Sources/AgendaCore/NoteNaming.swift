import Foundation

/// File names for Markdown notes: `2026-10-21 Normalización.md`.
public enum NoteNaming {
    /// Characters macOS or other apps choke on in file names.
    private static let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines).union(.controlCharacters)

    public static let notesFolderName = "Notas"

    /// Readable, safe title for a file name (never empty).
    public static func sanitize(_ title: String) -> String {
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((trimmed.isEmpty ? "Untitled" : trimmed).prefix(120))
    }

    /// `2026-10-21 Title.md`, adding ` (2)`, ` (3)`… when `exists` says the name is taken.
    public static func fileName(title: String, date: Date, calendar: Calendar = .current, exists: (String) -> Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let base = "\(stamp) \(sanitize(title))"
        var candidate = "\(base).md"
        var counter = 2
        while exists(candidate) {
            candidate = "\(base) (\(counter)).md"
            counter += 1
        }
        return candidate
    }

    /// Display title of a note file: first `# Heading` if present, else the file name without date and extension.
    public static func displayTitle(fileName: String, contents: String?) -> String {
        if let contents {
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true).prefix(5) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            }
        }
        var name = (fileName as NSString).deletingPathExtension
        if let match = name.firstMatch(of: #/^\d{4}-\d{2}-\d{2} /#) { name.removeSubrange(match.range) }
        return name
    }

    /// Initial contents for a new note.
    public static func template(title: String) -> String { "# \(title)\n\n" }
}
