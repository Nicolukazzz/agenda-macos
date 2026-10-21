import Foundation

/// Builds short `#tags` for course names: `BD` → `bd`, `Sistemas Operativos` → `so`, `Gestión TI` → `gti`.
public enum TagSuggester {
    private static let stopWords: Set<String> = ["de", "del", "la", "las", "el", "los", "y", "e", "en", "a", "para", "por", "con"]

    /// Lowercase, no accents, only letters and digits. Used for tags and for matching what the user types.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    public static func suggest(for name: String, existing: Set<String> = []) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let significant = words.filter { !stopWords.contains($0.lowercased()) }

        var base: String
        if significant.count <= 1 {
            let word = significant.first ?? name
            base = normalize(word)
            if base.count > 8 { base = String(base.prefix(8)) }
        } else {
            // Short all-caps words (acronyms like "TI") are kept whole; others contribute their initial.
            base = significant.map { word in
                let isAcronym = word.count <= 3 && word == word.uppercased()
                return isAcronym ? normalize(word) : String(normalize(word).prefix(1))
            }.joined()
        }
        if base.isEmpty { base = "materia" }

        var candidate = base
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)\(counter)"
            counter += 1
        }
        return candidate
    }
}

/// Course colors, readable in light and dark mode.
public enum CoursePalette {
    public static let hexColors: [String] = [
        "#4F7BF7", "#E5534B", "#3FB27F", "#F0A33A", "#9B6DDB",
        "#2BB0C7", "#E06AA6", "#8A9A2B", "#D9763B", "#6B7A90",
    ]

    public static func color(at index: Int) -> String {
        hexColors[((index % hexColors.count) + hexColors.count) % hexColors.count]
    }
}
