import Foundation

/// A course or area that can be referenced with `#tag`.
public struct TagCandidate: Sendable, Equatable {
    public var tag: String
    public var name: String

    public init(tag: String, name: String) {
        self.tag = tag
        self.name = name
    }
}

/// `#tag` autocompletion and extraction for titles typed by the user.
public enum TagCompletion {
    /// The partial tag being typed at the end of `text` (`"Estudiar #b"` → `"b"`, `"#"` → `""`), or nil.
    public static func currentQuery(in text: String) -> String? {
        guard let hashIndex = text.lastIndex(of: "#") else { return nil }
        let after = text[text.index(after: hashIndex)...]
        guard !after.contains(where: \.isWhitespace) else { return nil }
        // `#` must start a word.
        if hashIndex > text.startIndex, !text[text.index(before: hashIndex)].isWhitespace { return nil }
        return String(after)
    }

    /// Replaces the partial tag at the end of `text` with `#tag ` (trailing space so typing continues).
    public static func complete(_ text: String, with tag: String) -> String {
        guard currentQuery(in: text) != nil, let hashIndex = text.lastIndex(of: "#") else {
            return text + (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "#\(tag) "
        }
        return String(text[..<hashIndex]) + "#\(tag) "
    }

    /// Candidates for `query`: tag prefix first, then name-word prefix, then substring. Empty query lists all.
    public static func suggestions(for query: String, in candidates: [TagCandidate]) -> [TagCandidate] {
        let q = TagSuggester.normalize(query)
        guard !q.isEmpty else { return candidates }
        func rank(_ candidate: TagCandidate) -> Int? {
            let tag = TagSuggester.normalize(candidate.tag)
            let words = candidate.name.split(whereSeparator: \.isWhitespace).map { TagSuggester.normalize(String($0)) }
            let name = TagSuggester.normalize(candidate.name)
            if tag.hasPrefix(q) { return 0 }
            if words.contains(where: { $0.hasPrefix(q) }) { return 1 }
            // Substring matches are too noisy for a single letter.
            if q.count >= 2, tag.contains(q) || name.contains(q) { return 2 }
            return nil
        }
        return candidates
            .compactMap { candidate in rank(candidate).map { (candidate, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Pulls known `#tags` out of a title: `"Estudiar #bd parcial"` → (`"Estudiar parcial"`, `"bd"`).
    /// Unknown tags stay in the title so no text is lost. Only the first known tag is used.
    public static func extract(from text: String, known: Set<String>) -> (title: String, tag: String?) {
        var found: String?
        var kept: [Substring] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if word.hasPrefix("#"), word.count > 1 {
                let tag = TagSuggester.normalize(String(word.dropFirst()))
                if known.contains(tag) {
                    if found == nil { found = tag }
                    continue
                }
            }
            kept.append(word)
        }
        return (kept.joined(separator: " "), found)
    }
}
