import AgendaCore
import SwiftUI

/// Renders a note's Markdown with the app's type scale. Inline styles (bold, italic, `code`, links)
/// come from `AttributedString(markdown:)`; blocks come from `MarkdownBlocks`.
struct MarkdownPreview: View {
    let source: String

    var body: some View {
        let blocks = MarkdownBlocks.parse(source)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, index == 0 ? 0 : spacing(before: block, after: blocks[index - 1]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? Theme.Space.s : Theme.Space.xs)
        case .paragraph(let text):
            Text(inline(text)).font(Theme.Font.body).lineSpacing(3)
        case .bullet(let indent, let text):
            listRow(indent: indent, marker: Text("•").foregroundStyle(.secondary), text: text)
        case .numbered(let indent, let number, let text):
            listRow(indent: indent, marker: Text("\(number).").monospacedDigit().foregroundStyle(.secondary), text: text)
        case .checkbox(let indent, let checked, let text):
            listRow(indent: indent,
                    marker: Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)),
                    text: text, struck: checked)
        case .quote(let text):
            HStack(spacing: Theme.Space.m) {
                RoundedRectangle(cornerRadius: 1.5).fill(.tint.opacity(0.6)).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(_, let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.s) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell)).fontWeight(index == 0 ? .semibold : .regular)
                        }
                    }
                    if index == 0 { Divider() }
                }
            }
            .padding(Theme.Space.m)
            .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        case .rule:
            Divider().padding(.vertical, Theme.Space.xs)
        }
    }

    /// Tight spacing inside lists, roomier between other blocks.
    private func spacing(before block: MarkdownBlock, after previous: MarkdownBlock) -> CGFloat {
        isListItem(block) && isListItem(previous) ? Theme.Space.xs : Theme.Space.m
    }

    private func isListItem(_ block: MarkdownBlock) -> Bool {
        switch block {
        case .bullet, .numbered, .checkbox: true
        default: false
        }
    }

    private func listRow(indent: Int, marker: some View, text: String, struck: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            marker.frame(minWidth: 14, alignment: .trailing)
            Text(inline(text)).strikethrough(struck).foregroundStyle(struck ? .secondary : .primary)
        }
        .padding(.leading, CGFloat(indent) * Theme.Space.l)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(.title, design: .rounded).weight(.bold)
        case 2: .system(.title2, design: .rounded).weight(.semibold)
        case 3: .system(.title3, design: .rounded).weight(.semibold)
        default: .headline
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
