import AgendaCore
import SwiftData
import SwiftUI

/// Text field that suggests the active semester's areas while typing `#`.
/// ↑/↓ choose, Return or Tab accept, Esc hides. Clicking a suggestion also accepts it.
struct TagCompletionField: View {
    let placeholder: String
    @Binding var text: String
    let areas: [Area]
    /// Large borderless field for the main title of an editor.
    var prominent = false
    var onSubmit: () -> Void = {}

    @State private var highlighted = 0
    @State private var dismissedQuery: String?
    @FocusState private var focused: Bool

    private var query: String? { TagCompletion.currentQuery(in: text) }

    private var suggestions: [Area] {
        guard let query, query != dismissedQuery else { return [] }
        let candidates = areas.map { TagCandidate(tag: $0.tag, name: $0.name) }
        let ranked = TagCompletion.suggestions(for: query, in: candidates).map(\.tag)
        return ranked.compactMap { tag in areas.first { $0.tag == tag } }
    }

    var body: some View {
        field
            .focused($focused)
            .onSubmit {
                if !suggestions.isEmpty { accept(suggestions[clampedIndex]) } else { onSubmit() }
            }
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.tab) {
                guard !suggestions.isEmpty else { return .ignored }
                accept(suggestions[clampedIndex])
                return .handled
            }
            .onKeyPress(.escape) {
                guard !suggestions.isEmpty else { return .ignored }
                dismissedQuery = query
                return .handled
            }
            .onChange(of: text) {
                highlighted = 0
                if query != dismissedQuery { dismissedQuery = nil }
            }
            // An overlay instead of a popover: a popover would take keyboard focus away from the field.
            .overlay(alignment: .topLeading) {
                if focused && !suggestions.isEmpty {
                    suggestionList
                        .offset(y: prominent ? 38 : 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .animation(Theme.Motion.snappy, value: suggestions.isEmpty)
            .zIndex(10)
    }

    @ViewBuilder
    private var field: some View {
        if prominent {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(.title2, design: .rounded).weight(.semibold))
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var clampedIndex: Int { min(max(highlighted, 0), max(suggestions.count - 1, 0)) }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        highlighted = (clampedIndex + delta + suggestions.count) % suggestions.count
        return .handled
    }

    private func accept(_ area: Area) {
        text = TagCompletion.complete(text, with: area.tag)
        dismissedQuery = nil
        focused = true
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ForEach(Array(suggestions.prefix(8).enumerated()), id: \.element.liveID) { index, area in
                Button {
                    accept(area)
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        AreaDot(hex: area.colorHex)
                        Text(area.name).lineLimit(1)
                        Spacer(minLength: Theme.Space.m)
                        Text("#\(area.tag)").font(Theme.Font.tag).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.vertical, Theme.Space.xs + 1)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .background {
                        if index == clampedIndex {
                            RoundedRectangle(cornerRadius: Theme.Radius.control).fill(.tint.opacity(0.18))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Space.xs + 2)
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
