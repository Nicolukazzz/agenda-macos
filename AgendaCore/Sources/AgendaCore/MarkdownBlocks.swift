import Foundation

/// Block-level Markdown for note previews. Inline styling (bold, italic, code, links)
/// is left inside the text and rendered by `AttributedString(markdown:)` in the app.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, number: Int, text: String)
    case checkbox(indent: Int, checked: Bool, text: String)
    case quote(String)
    case code(language: String, text: String)
    case table(rows: [[String]])
    case rule
}

public enum MarkdownBlocks {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [[String]] = []
        var code: (language: String, lines: [String])?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))); quote = [] }
            if !table.isEmpty { blocks.append(.table(rows: table)); table = [] }
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(rawLine)
                    code = open
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                code = (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
                continue
            }
            if trimmed.isEmpty { flush(); continue }

            let indent = (line.prefix { $0 == " " }.count) / 2

            if let match = trimmed.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                flush()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
            } else if trimmed.wholeMatch(of: /(\*\s*){3,}|(-\s*){3,}|(_\s*){3,}/) != nil {
                flush()
                blocks.append(.rule)
            } else if let match = trimmed.wholeMatch(of: /[-*+]\s+\[([ xX])\]\s+(.*)/) {
                flush()
                blocks.append(.checkbox(indent: indent, checked: match.1 != " ", text: String(match.2)))
            } else if let match = trimmed.wholeMatch(of: /[-*+]\s+(.*)/) {
                flush()
                blocks.append(.bullet(indent: indent, text: String(match.1)))
            } else if let match = trimmed.wholeMatch(of: /(\d+)[.)]\s+(.*)/) {
                flush()
                blocks.append(.numbered(indent: indent, number: Int(match.1) ?? 1, text: String(match.2)))
            } else if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !table.isEmpty { flush() }
                quote.append(String(trimmed.drop { $0 == ">" }).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty || !quote.isEmpty { flush() }
                let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // Skip the |---|---| separator row.
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(cells) }
            } else {
                if !quote.isEmpty || !table.isEmpty { flush() }
                paragraph.append(trimmed)
            }
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
