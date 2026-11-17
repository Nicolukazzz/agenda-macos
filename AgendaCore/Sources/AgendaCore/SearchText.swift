import Foundation

/// Matching for global search: case- and accent-insensitive ("matematicas" finds "Matemáticas").
public enum SearchText {
    public static func matches(_ text: String, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The line of `text` holding `query`, trimmed to about `width` characters around it. Nil without a match.
    public static func snippet(_ text: String, _ query: String, width: Int = 90) -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let hit = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let lineStart = text[..<hit.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[hit.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let before = text.distance(from: lineStart, to: hit.lowerBound)
        let start = before > width / 3 ? text.index(hit.lowerBound, offsetBy: -(width / 3)) : lineStart
        let end = text.index(start, offsetBy: width, limitedBy: lineEnd) ?? lineEnd
        var line = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
        // Markdown marks at the start of a line add nothing to a one-line preview.
        while let first = line.first, "#>-*".contains(first) { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return (start > lineStart ? "…" : "") + line + (end < lineEnd ? "…" : "")
    }
}
