import SwiftUI

// Grouped content, iOS Settings style: cards made of rows with a leading icon.

/// Title (+ optional detail) above a card or list.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title).font(Theme.Font.sectionTitle)
            if let detail {
                Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, Theme.Space.xs)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title: title, detail: detail, accessory: { EmptyView() })
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Row inside a `Card`: icon, then content (leading-aligned; add `Spacer()` to push trailing controls).
struct CardRow<Content: View>: View {
    var icon: String?
    var iconColor: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: Theme.Size.rowIcon)
                    .accessibilityHidden(true)
            }
            HStack(spacing: Theme.Space.s) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.m + 2)
        .padding(.vertical, Theme.Space.s + 2)
        .frame(minHeight: 44)
    }
}

/// Separator between card rows, inset past the icon column.
struct CardDivider: View {
    var inset: CGFloat = Theme.Size.rowInset
    var body: some View { Divider().padding(.leading, inset) }
}

/// Small explanatory text under a row, aligned with the row content.
struct CardNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Theme.Size.rowInset)
            .padding(.trailing, Theme.Space.l)
            .padding(.bottom, Theme.Space.s + 2)
    }
}

/// Text field that blends into a card row.
struct CardTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .lineLimit(axis == .vertical ? 1...5 : 1...1)
    }
}

/// Label + trailing switch inside a card row.
struct CardToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Text(title)
        Spacer()
        Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
    }
}
